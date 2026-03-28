`timescale 1ns / 1ps

module dense #(
    parameter INPUT_SIZE  = 2944,     // Input neurons (from flatten)
    parameter OUTPUT_SIZE = 5,      // Output neurons (num classes)
    parameter WEIGHT_FILE = "dense_weights.mem"
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire signed [15:0]       data_in  [0:INPUT_SIZE-1],
    output reg  signed [15:0]       data_out [0:OUTPUT_SIZE-1],
    output reg                      done
);

    // ─── Total weights ────────────────────────────────────────────────
    localparam TOTAL_WEIGHTS = INPUT_SIZE * OUTPUT_SIZE;

    // ─── Weight BRAM ──────────────────────────────────────────────────
    (* ram_style = "block" *)
    reg signed [7:0] weights [0:TOTAL_WEIGHTS-1];

    initial begin
        $readmemh(WEIGHT_FILE, weights);
    end

    // ─── Bias ─────────────────────────────────────────────────────────
    reg signed [15:0] bias [0:OUTPUT_SIZE-1];

    initial begin
        $readmemh("dense_bias.mem", bias);
    end

    // ─── FSM States ───────────────────────────────────────────────────
    localparam D_IDLE    = 2'd0;    // Waiting for start
    localparam D_MAC     = 2'd1;    // Multiply accumulate
    localparam D_RELU    = 2'd2;    // ReLU + bias
    localparam D_DONE    = 2'd3;    // All neurons computed

    reg [1:0] state;

    // ─── Internal Registers ───────────────────────────────────────────
    reg [7:0]        neuron_idx;    // Current output neuron (0 to OUTPUT_SIZE-1)
    reg [7:0]        input_idx;     // Current input neuron  (0 to INPUT_SIZE-1)
    reg signed [23:0] accumulator;  // Wide accumulator for MAC

    // ─── Output Buffer ────────────────────────────────────────────────
    reg signed [15:0] out_buf [0:OUTPUT_SIZE-1];

    // ─── DSP48 MAC ────────────────────────────────────────────────────
    // Vivado infers DSP48 from this signed multiply
    wire signed [7:0]  weight_val = weights[neuron_idx * INPUT_SIZE + input_idx];
    wire signed [15:0] input_val  = data_in[input_idx];
    wire signed [23:0] product    = weight_val * input_val; // DSP48 inferred

    // ─── Main FSM ─────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= D_IDLE;
            neuron_idx  <= 8'd0;
            input_idx   <= 8'd0;
            accumulator <= 24'd0;
            done        <= 1'b0;
        end
        else begin
            done <= 1'b0;

            case (state)

                // ── Wait for start ────────────────────────────────────
                D_IDLE: begin
                    if (start) begin
                        neuron_idx  <= 8'd0;
                        input_idx   <= 8'd0;
                        accumulator <= 24'd0;
                        state       <= D_MAC;
                    end
                end

                // ── MAC across all input neurons ──────────────────────
                // For each output neuron, multiply every input
                // by its corresponding weight and accumulate
                D_MAC: begin
                    accumulator <= accumulator + product;

                    if (input_idx == INPUT_SIZE - 1) begin
                        // All inputs accumulated for this neuron
                        input_idx <= 8'd0;
                        state     <= D_RELU;
                    end
                    else begin
                        input_idx <= input_idx + 1;
                    end
                end

                // ── Bias + ReLU ───────────────────────────────────────
                // Add bias then apply ReLU
                // Skip ReLU on last layer (output layer uses softmax
                // but for argmax classification ReLU is fine here)
                D_RELU: begin
                    begin : relu_block
                        reg signed [15:0] result;
                        result = accumulator[23:8] + bias[neuron_idx];

                        // ReLU on hidden layers only
                        // Last layer (OUTPUT_SIZE neurons) keeps raw value
                        // so argmax in cnn_top works correctly
                        if (neuron_idx < OUTPUT_SIZE - 1) begin
                            if (result < 0)
                                out_buf[neuron_idx] <= 16'd0;
                            else
                                out_buf[neuron_idx] <= result;
                        end
                        else begin
                            // Last neuron — no ReLU
                            out_buf[neuron_idx] <= result;
                        end
                    end

                    // Reset accumulator for next neuron
                    accumulator <= 24'd0;

                    if (neuron_idx == OUTPUT_SIZE - 1) begin
                        // All neurons done
                        data_out <= out_buf;
                        state    <= D_DONE;
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