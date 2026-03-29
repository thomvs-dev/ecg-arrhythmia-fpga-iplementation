`timescale 1ns / 1ps

module conv1d #(
    parameter INPUT_LEN   = 186,    // Length of input signal
    parameter KERNEL_SIZE = 5,      // Size of conv kernel
    parameter NUM_FILTERS = 32,     // Number of filters
    parameter WEIGHT_FILE = "conv1_weights.mem", // Weight file
    parameter BIAS_FILE   = "conv1_bias.mem"   // Bias file
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              start,
    input  wire [INPUT_LEN*8-1:0]            signal_in_flat,   // Flattened: INPUT_LEN x 8-bit
    output wire [NUM_FILTERS*16-1:0]         conv_out_flat,    // Flattened: NUM_FILTERS x 16-bit
    output reg                               done
);

    // ─── Parameters ───────────────────────────────────────────────────
    // Output length after convolution (no padding)
    localparam OUTPUT_LEN = INPUT_LEN - KERNEL_SIZE + 1;

    // Total weights = NUM_FILTERS × KERNEL_SIZE
    localparam TOTAL_WEIGHTS = NUM_FILTERS * KERNEL_SIZE;

    // ─── Unpack flattened input into internal array ───────────────────
    wire signed [7:0] signal_in [0:INPUT_LEN-1];
    genvar gi;
    generate
        for (gi = 0; gi < INPUT_LEN; gi = gi + 1) begin : unpack_input
            assign signal_in[gi] = signal_in_flat[gi*8 +: 8];
        end
    endgenerate

    // ─── Pack internal output array into flat output ──────────────────
    reg signed [15:0] result_buf [0:NUM_FILTERS-1];
    genvar go;
    generate
        for (go = 0; go < NUM_FILTERS; go = go + 1) begin : pack_output
            assign conv_out_flat[go*16 +: 16] = result_buf[go];
        end
    endgenerate

    // ─── Weight BRAM ──────────────────────────────────────────────────
    // Stores Int8 weights loaded from .mem file
    (* ram_style = "block" *)
    reg signed [7:0] weights [0:TOTAL_WEIGHTS-1];

    initial begin
        $readmemh(WEIGHT_FILE, weights);
    end

    // ─── Bias BRAM ────────────────────────────────────────────────────
    reg signed [15:0] bias [0:NUM_FILTERS-1];

    initial begin
        $readmemh(BIAS_FILE, bias);
    end

    // ─── FSM States ───────────────────────────────────────────────────
    localparam C_IDLE    = 3'd0;    // Waiting for start
    localparam C_MAC     = 3'd1;    // Performing multiply-accumulate
    localparam C_RELU    = 3'd2;    // Applying ReLU activation
    localparam C_DONE    = 3'd3;    // All filters computed

    reg [2:0] state;

    // ─── Internal Registers ───────────────────────────────────────────
    reg [15:0] filter_idx;      // Current filter being computed
    reg [15:0] pos_idx;         // Current position in signal
    reg [15:0] k_idx;           // Current kernel position
    reg [15:0] accum_idx;       // Items accumulated
    reg [15:0] weight_idx;      // Sequential address for block ram

    reg signed [23:0] accumulator;

    // ─── Pipeline Registers (inferences BRAM) ─────────────────────────
    reg signed [7:0] weight_reg;
    reg signed [7:0] signal_reg;

    always @(posedge clk) begin
        weight_reg <= weights[weight_idx];
        signal_reg <= signal_in[pos_idx + k_idx];
    end

    // ─── DSP48 MAC ────────────────────────────────────────────────────
    wire signed [15:0] product = weight_reg * signal_reg; // 8x8 = 16 bit DSP inference

    // ─── Main FSM ─────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= C_IDLE;
            filter_idx  <= 0;
            pos_idx     <= 0;
            k_idx       <= 0;
            accum_idx   <= 0;
            weight_idx  <= 0;
            accumulator <= 24'd0;
            done        <= 1'b0;
        end
        else begin
            done <= 1'b0;

            case (state)

                // ── Wait for start signal ─────────────────────────────
                C_IDLE: begin
                    if (start) begin
                        filter_idx  <= 0;
                        pos_idx     <= 0;
                        k_idx       <= 0;
                        accum_idx   <= 0;
                        weight_idx  <= 0;
                        accumulator <= 24'd0;
                        state       <= C_MAC;
                    end
                end

                // ── Multiply Accumulate ───────────────────────────────
                C_MAC: begin
                    // Address request for next pipeline stage
                    if (k_idx < KERNEL_SIZE) begin
                        k_idx      <= k_idx + 1;
                        weight_idx <= weight_idx + 1;
                    end

                    // Accumulation from previous pipeline stage
                    if (k_idx > 0) begin
                        accumulator <= accumulator + product;
                        accum_idx   <= accum_idx + 1;

                        if (accum_idx == KERNEL_SIZE - 1) begin
                            state <= C_RELU;
                        end
                    end
                end

                // ── ReLU Activation ───────────────────────────────────
                C_RELU: begin
                    begin : relu_block
                        reg signed [15:0] mac_result;
                        mac_result = accumulator[23:8] + bias[filter_idx];

                        if (mac_result < 0)
                            result_buf[filter_idx] <= 16'd0;
                        else
                            result_buf[filter_idx] <= mac_result;
                    end

                    // Reset for next filter
                    accumulator <= 24'd0;
                    k_idx       <= 0;
                    accum_idx   <= 0;

                    if (filter_idx == NUM_FILTERS - 1) begin
                        filter_idx <= 0;
                        if (pos_idx == OUTPUT_LEN - 1) begin
                            state <= C_DONE;
                        end
                        else begin
                            pos_idx    <= pos_idx + 1;
                            weight_idx <= 0; // Reset weights for next position
                            state      <= C_MAC;
                        end
                    end
                    else begin
                        filter_idx <= filter_idx + 1;
                        state      <= C_MAC;
                        // weight_idx continues unmodified to the next filter chunk
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