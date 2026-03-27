`timescale 1ns / 1ps

module dense #(
    parameter INPUT_SIZE  = 64,
    parameter OUTPUT_SIZE = 5,
    parameter WEIGHT_FILE = "dense_weights.mem"
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,
    input  wire [16*INPUT_SIZE-1:0]      data_in_flat,
    output wire [16*OUTPUT_SIZE-1:0]     data_out_flat,
    output reg                           done
);

    localparam TOTAL_WEIGHTS = INPUT_SIZE * OUTPUT_SIZE;

    wire signed [15:0] data_in [0:INPUT_SIZE-1];
    genvar gi;
    generate
        for (gi = 0; gi < INPUT_SIZE; gi = gi + 1) begin : unpack_in
            assign data_in[gi] = data_in_flat[gi*16 +: 16];
        end
    endgenerate

    (* ram_style = "block" *)
    reg signed [7:0] weights [0:TOTAL_WEIGHTS-1];
    initial begin
        $readmemh(WEIGHT_FILE, weights);
    end

    reg signed [15:0] bias [0:OUTPUT_SIZE-1];
    initial begin
        $readmemh("dense_bias.mem", bias);
    end

    localparam D_IDLE = 2'd0;
    localparam D_MAC  = 2'd1;
    localparam D_RELU = 2'd2;
    localparam D_DONE = 2'd3;
    reg [1:0] state;

    reg [7:0]          neuron_idx;
    reg [7:0]          input_idx;
    reg signed [23:0]  accumulator;

    reg signed [15:0] out_buf [0:OUTPUT_SIZE-1];

    generate
        for (gi = 0; gi < OUTPUT_SIZE; gi = gi + 1) begin : pack_out
            assign data_out_flat[gi*16 +: 16] = out_buf[gi];
        end
    endgenerate

    wire signed [7:0]  weight_val = weights[neuron_idx * INPUT_SIZE + input_idx];
    wire signed [15:0] input_val  = data_in[input_idx];
    wire signed [23:0] product    = weight_val * input_val;

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
                D_IDLE: begin
                    if (start) begin
                        neuron_idx  <= 8'd0;
                        input_idx   <= 8'd0;
                        accumulator <= 24'd0;
                        state       <= D_MAC;
                    end
                end
                D_MAC: begin
                    accumulator <= accumulator + product;
                    if (input_idx == INPUT_SIZE - 1) begin
                        input_idx <= 8'd0;
                        state     <= D_RELU;
                    end
                    else begin
                        input_idx <= input_idx + 1;
                    end
                end
                D_RELU: begin
                    begin : relu_block
                        reg signed [15:0] result;
                        result = accumulator[23:8] + bias[neuron_idx];
                        if (neuron_idx < OUTPUT_SIZE - 1) begin
                            if (result < 0)
                                out_buf[neuron_idx] <= 16'd0;
                            else
                                out_buf[neuron_idx] <= result;
                        end
                        else begin
                            out_buf[neuron_idx] <= result;
                        end
                    end
                    accumulator <= 24'd0;
                    if (neuron_idx == OUTPUT_SIZE - 1) begin
                        state <= D_DONE;
                    end
                    else begin
                        neuron_idx <= neuron_idx + 1;
                        state      <= D_MAC;
                    end
                end
                D_DONE: begin
                    done  <= 1'b1;
                    state <= D_IDLE;
                end
                default: state <= D_IDLE;
            endcase
        end
    end

endmodule