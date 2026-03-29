`timescale 1ns / 1ps

module maxpool #(
    parameter NUM_FILTERS = 64,     // Number of input channels
    parameter POOL_SIZE   = 3,      // Pooling window size
    parameter STRIDE      = 2       // Stride of pooling window
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              start,
    input  wire [NUM_FILTERS*16-1:0]         data_in_flat,    // Flattened: NUM_FILTERS x 16-bit
    output wire [NUM_FILTERS*16-1:0]         data_out_flat,   // Flattened: OUTPUT_LEN x 16-bit (same width for simplicity)
    output reg                               done
);

    // ─── Parameters ───────────────────────────────────────────────────
    // Output length after pooling
    localparam OUTPUT_LEN = (NUM_FILTERS - POOL_SIZE) / STRIDE + 1;

    // ─── Unpack flattened input into internal array ───────────────────
    wire signed [15:0] data_in [0:NUM_FILTERS-1];
    genvar gi;
    generate
        for (gi = 0; gi < NUM_FILTERS; gi = gi + 1) begin : unpack_input
            assign data_in[gi] = data_in_flat[gi*16 +: 16];
        end
    endgenerate

    // ─── Pack internal output array into flat output ──────────────────
    // Output buffer drives the flat output continuously
    reg signed [15:0] out_buf [0:OUTPUT_LEN-1];
    genvar go;
    generate
        for (go = 0; go < NUM_FILTERS; go = go + 1) begin : pack_output
            // For indices within OUTPUT_LEN, connect to out_buf; rest are zero
            if (go < OUTPUT_LEN) begin : valid_out
                assign data_out_flat[go*16 +: 16] = out_buf[go];
            end else begin : zero_pad
                assign data_out_flat[go*16 +: 16] = 16'd0;
            end
        end
    endgenerate

    // ─── FSM States ───────────────────────────────────────────────────
    localparam P_IDLE    = 2'd0;    // Waiting for start
    localparam P_POOL    = 2'd1;    // Computing max in window
    localparam P_NEXT    = 2'd2;    // Moving to next window
    localparam P_DONE    = 2'd3;    // All windows computed

    reg [1:0] state;

    // ─── Internal Registers ───────────────────────────────────────────
    reg [7:0]        window_idx;    // Current window position
    reg [7:0]        pool_idx;      // Position inside current window
    reg signed [15:0] current_max; // Max value found so far in window
    reg [7:0]        out_idx;       // Output buffer index

    // ─── Current value being compared ─────────────────────────────────
    wire signed [15:0] current_val = data_in[window_idx + pool_idx];

    // ─── Main FSM ─────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= P_IDLE;
            window_idx  <= 8'd0;
            pool_idx    <= 8'd0;
            out_idx     <= 8'd0;
            current_max <= 16'h8000;    // Minimum signed 16bit value
            done        <= 1'b0;
        end
        else begin
            done <= 1'b0;

            case (state)

                // ── Wait for start ────────────────────────────────────
                P_IDLE: begin
                    if (start) begin
                        window_idx  <= 8'd0;
                        pool_idx    <= 8'd0;
                        out_idx     <= 8'd0;
                        current_max <= 16'h8000;
                        state       <= P_POOL;
                    end
                end

                // ── Find max in current window ────────────────────────
                P_POOL: begin
                    // Compare current value with running max
                    if (current_val > current_max)
                        current_max <= current_val;

                    if (pool_idx == POOL_SIZE - 1) begin
                        // Window complete - store max and move on
                        pool_idx <= 8'd0;
                        state    <= P_NEXT;
                    end
                    else begin
                        pool_idx <= pool_idx + 1;
                    end
                end

                // ── Store result, advance window ──────────────────────
                P_NEXT: begin
                    // Store max value of this window
                    out_buf[out_idx] <= current_max;
                    out_idx          <= out_idx + 1;

                    // Reset max for next window
                    current_max <= 16'h8000;

                    // Advance window by stride
                    window_idx <= window_idx + STRIDE;

                    if (out_idx == OUTPUT_LEN - 1) begin
                        // All windows done
                        state    <= P_DONE;
                    end
                    else begin
                        state <= P_POOL;
                    end
                end

                // ── Done ──────────────────────────────────────────────
                P_DONE: begin
                    done  <= 1'b1;
                    state <= P_IDLE;
                end

                default: state <= P_IDLE;

            endcase
        end
    end

endmodule