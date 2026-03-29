`timescale 1ns / 1ps

module conv1d #(
    parameter INPUT_LEN   = 186,    // Length of input signal
    parameter KERNEL_SIZE = 5,      // Size of conv kernel
    parameter NUM_FILTERS = 32,     // Number of filters
    parameter WEIGHT_FILE = "conv1_weights.mem" // Weight file
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        start,
    input  wire signed [7:0]           signal_in [0:INPUT_LEN-1],
    output reg  signed [15:0]          conv_out  [0:NUM_FILTERS-1],
    output reg                         done
);

    // ─── Parameters ───────────────────────────────────────────────────
    // Output length after convolution (no padding)
    localparam OUTPUT_LEN = INPUT_LEN - KERNEL_SIZE + 1;

    // Total weights = NUM_FILTERS × KERNEL_SIZE
    localparam TOTAL_WEIGHTS = NUM_FILTERS * KERNEL_SIZE;

    // ─── Weight BRAM ──────────────────────────────────────────────────
    // Stores Int8 weights loaded from .mem file
    // Layout: filter 0 kernel, filter 1 kernel, ... filter 63 kernel
    (* ram_style = "block" *)
    reg signed [7:0] weights [0:TOTAL_WEIGHTS-1];

    initial begin
        $readmemh(WEIGHT_FILE, weights);
    end

    // ─── Bias BRAM ────────────────────────────────────────────────────
    reg signed [15:0] bias [0:NUM_FILTERS-1];

    initial begin
        $readmemh("conv1_bias.mem", bias);
    end

    // ─── Internal Registers ───────────────────────────────────────────
    reg [7:0]  filter_idx;      // Current filter being computed (0 to 63)
    reg [7:0]  pos_idx;         // Current position in signal (0 to OUTPUT_LEN-1)
    reg [2:0]  k_idx;           // Current kernel position (0 to KERNEL_SIZE-1)

    // Accumulator — wide enough to hold sum of 6 × (8bit × 8bit) = 6 × 16bit
    reg signed [23:0] accumulator;

    // Partial MAC result — using DSP48 slice
    reg signed [15:0] mac_result;

    // ─── FSM States ───────────────────────────────────────────────────
    localparam C_IDLE    = 2'd0;    // Waiting for start
    localparam C_MAC     = 2'd1;    // Performing multiply-accumulate
    localparam C_RELU    = 2'd2;    // Applying ReLU activation
    localparam C_DONE    = 2'd3;    // All filters computed

    reg [1:0] state;

    // ─── Intermediate result buffer ───────────────────────────────────
    // Stores one full set of filter outputs before maxpool
    reg signed [15:0] result_buf [0:NUM_FILTERS-1];

    // ─── DSP48 MAC Unit ───────────────────────────────────────────────
    // Vivado infers DSP48 slices from this multiply-accumulate pattern
    // Do NOT change this structure or Vivado won't infer DSP48
    wire signed [7:0]  weight_val = weights[filter_idx * KERNEL_SIZE + k_idx];
    wire signed [7:0]  signal_val = signal_in[pos_idx + k_idx];
    wire signed [15:0] product    = weight_val * signal_val; // DSP48 inferred here

    // ─── Main FSM ─────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= C_IDLE;
            filter_idx  <= 8'd0;
            pos_idx     <= 8'd0;
            k_idx       <= 3'd0;
            accumulator <= 24'd0;
            done        <= 1'b0;
        end
        else begin
            done <= 1'b0;

            case (state)

                // ── Wait for start signal ─────────────────────────────
                C_IDLE: begin
                    if (start) begin
                        filter_idx  <= 8'd0;
                        pos_idx     <= 8'd0;
                        k_idx       <= 3'd0;
                        accumulator <= 24'd0;
                        state       <= C_MAC;
                    end
                end

                // ── Multiply Accumulate ───────────────────────────────
                // For each filter, slide kernel across signal
                // accumulate products, then apply ReLU
                C_MAC: begin
                    // Accumulate MAC result (DSP48 inferred)
                    accumulator <= accumulator + product;

                    if (k_idx == KERNEL_SIZE - 1) begin
                        // Finished one kernel position — go to ReLU
                        k_idx <= 3'd0;
                        state <= C_RELU;
                    end
                    else begin
                        k_idx <= k_idx + 1;
                    end
                end

                // ── ReLU Activation ───────────────────────────────────
                // ReLU = max(0, x)
                // Also add bias here
                C_RELU: begin
                    mac_result = accumulator[23:8] + bias[filter_idx];

                    // ReLU — zero clip negative values
                    if (mac_result < 0)
                        result_buf[filter_idx] <= 16'd0;
                    else
                        result_buf[filter_idx] <= mac_result;

                    // Reset accumulator for next filter
                    accumulator <= 24'd0;

                    // Move to next filter
                    if (filter_idx == NUM_FILTERS - 1) begin
                        // All filters done for this position
                        filter_idx <= 8'd0;

                        if (pos_idx == OUTPUT_LEN - 1) begin
                            // All positions done — copy to output
                            conv_out <= result_buf;
                            state    <= C_DONE;
                        end
                        else begin
                            pos_idx <= pos_idx + 1;
                            state   <= C_MAC;
                        end
                    end
                    else begin
                        filter_idx <= filter_idx + 1;
                        state      <= C_MAC;
                    end
                end

                // ── Done ──────────────────────────────────────────────
                C_DONE: begin
                    done  <= 1'b1;
                    state <= C_IDLE;
                end

                default: state <= C_IDLE;

            endcase
        end
    end

endmodule