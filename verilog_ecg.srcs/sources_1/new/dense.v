`timescale 1ns / 1ps

module dense #(
    parameter INPUT_SIZE  = 2944,     // Input neurons (from flatten)
    parameter OUTPUT_SIZE = 5,      // Output neurons (num classes)
    parameter WEIGHT_FILE = "dense_weights.mem",
    parameter BIAS_FILE   = "dense_bias.mem"
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              start,
    input  wire [INPUT_SIZE*16-1:0]          data_in_flat,    // Flattened: INPUT_SIZE x 16-bit
    output wire [OUTPUT_SIZE*16-1:0]         data_out_flat,   // Flattened: OUTPUT_SIZE x 16-bit
    output reg                               done
);

    // ─── Total weights ────────────────────────────────────────────────
    localparam TOTAL_WEIGHTS = INPUT_SIZE * OUTPUT_SIZE;

    // ─── Unpack flattened input into internal array ───────────────────
    wire signed [15:0] data_in [0:INPUT_SIZE-1];
    genvar gi;
    generate
        for (gi = 0; gi < INPUT_SIZE; gi = gi + 1) begin : unpack_input
            assign data_in[gi] = data_in_flat[gi*16 +: 16];
        end
    endgenerate

    // ─── Pack internal output array into flat output ──────────────────
    reg signed [15:0] out_buf [0:OUTPUT_SIZE-1];
    genvar go;
    generate
        for (go = 0; go < OUTPUT_SIZE; go = go + 1) begin : pack_output
            assign data_out_flat[go*16 +: 16] = out_buf[go];
        end
    endgenerate

    // ─── Weight BRAM ──────────────────────────────────────────────────
    (* ram_style = "block" *)
    (* cascade_height = 0 *)
    reg signed [7:0] weights [0:TOTAL_WEIGHTS-1];

    initial begin
        $readmemh(WEIGHT_FILE, weights);
    end

    // ─── Bias ─────────────────────────────────────────────────────────
    reg signed [15:0] bias [0:OUTPUT_SIZE-1];

    initial begin
        $readmemh(BIAS_FILE, bias);
    end

    // ─── FSM States ───────────────────────────────────────────────────
    localparam D_IDLE    = 3'd0;    // Waiting for start
    localparam D_MAC     = 3'd1;    // Multiply accumulate
    localparam D_RELU    = 3'd2;    // ReLU + bias
    localparam D_DONE    = 3'd3;    // All neurons computed

    reg [2:0] state;

    // ─── Internal Registers ───────────────────────────────────────────
    reg [15:0]       neuron_idx;    // Current output neuron (0 to OUTPUT_SIZE-1)
    reg [15:0]       input_idx;     // Current input neuron  (0 to INPUT_SIZE-1)
    reg [15:0]       accum_idx;     // Count of accumulated products
    (* keep = "true" *) reg [19:0]       weight_idx;    // Sequential address for weights

    reg signed [23:0] accumulator;  // Wide accumulator for MAC

    // ─── Pipeline Registers (inferences BRAM) ─────────────────────────
    reg signed [7:0]  weight_reg;
    reg signed [15:0] input_reg;

    always @(posedge clk) begin
        weight_reg <= weights[weight_idx];
        input_reg  <= data_in[input_idx];
    end

    // ─── DSP48 MAC ────────────────────────────────────────────────────
    wire signed [24:0] product = weight_reg * input_reg; // 8x16 = 24 bit

    // ─── Main FSM ─────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= D_IDLE;
            neuron_idx  <= 0;
            input_idx   <= 0;
            accum_idx   <= 0;
            weight_idx  <= 0;
            accumulator <= 24'd0;
            done        <= 1'b0;
        end
        else begin
            done <= 1'b0;

            case (state)

                // ── Wait for start ────────────────────────────────────
                D_IDLE: begin
                    if (start) begin
                        neuron_idx  <= 0;
                        input_idx   <= 0;
                        accum_idx   <= 0;
                        weight_idx  <= 0;
                        accumulator <= 24'd0;
                        state       <= D_MAC;
                    end
                end

                // ── MAC across all input neurons ──────────────────────
                D_MAC: begin
                    // Address generation for next cycle
                    if (input_idx < INPUT_SIZE) begin
                        input_idx  <= input_idx + 1;
                        weight_idx <= weight_idx + 1;
                    end

                    // Accumulation from previous cycle
                    if (input_idx > 0) begin
                        accumulator <= accumulator + product;
                        accum_idx   <= accum_idx + 1;

                        if (accum_idx == INPUT_SIZE - 1) begin
                            state <= D_RELU;
                        end
                    end
                end

                // ── Bias + ReLU ───────────────────────────────────────
                D_RELU: begin
                    begin : relu_block
                        reg signed [15:0] result;
                        result = accumulator[23:8] + bias[neuron_idx];

                        // ReLU on hidden layers only
                        if (neuron_idx < OUTPUT_SIZE - 1) begin
                            if (result < 0)
                                out_buf[neuron_idx] <= 16'd0;
                            else
                                out_buf[neuron_idx] <= result;
                        end
                        else begin
                            // Last neuron - no ReLU
                            out_buf[neuron_idx] <= result;
                        end
                    end

                    // Reset accumulator and indexes for next neuron
                    accumulator <= 24'd0;
                    input_idx   <= 0;
                    accum_idx   <= 0;
                    // weight_idx dynamically advanced, do not reset!

                    if (neuron_idx == OUTPUT_SIZE - 1) begin
                        state <= D_DONE;
                    end
                    else begin
                        neuron_idx <= neuron_idx + 1;
                        state      <= D_MAC;
                    end
                end

                // ── Done ──────────────────────────────────────────────
                D_DONE: begin
                    done  <= 1'b1;
                    state <= D_IDLE;
                end

                default: state <= D_IDLE;
            endcase
        end
    end

endmodule