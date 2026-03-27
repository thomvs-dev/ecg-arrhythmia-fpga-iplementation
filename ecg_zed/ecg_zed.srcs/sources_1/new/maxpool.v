`timescale 1ns / 1ps

module maxpool #(
    parameter NUM_FILTERS = 64,
    parameter POOL_SIZE   = 3,
    parameter STRIDE      = 2
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,
    input  wire [16*NUM_FILTERS-1:0]     data_in_flat,
    output wire [16*NUM_FILTERS-1:0]     data_out_flat,
    output reg                           done
);

    localparam OUTPUT_LEN = (NUM_FILTERS - POOL_SIZE) / STRIDE + 1;

    wire signed [15:0] data_in [0:NUM_FILTERS-1];
    genvar gi;
    generate
        for (gi = 0; gi < NUM_FILTERS; gi = gi + 1) begin : unpack_in
            assign data_in[gi] = data_in_flat[gi*16 +: 16];
        end
    endgenerate

    localparam P_IDLE = 2'd0;
    localparam P_POOL = 2'd1;
    localparam P_NEXT = 2'd2;
    localparam P_DONE = 2'd3;
    reg [1:0] state;

    reg [7:0]          window_idx;
    reg [7:0]          pool_idx;
    reg signed [15:0]  current_max;
    reg [7:0]          out_idx;

    reg signed [15:0] out_buf [0:NUM_FILTERS-1];

    generate
        for (gi = 0; gi < NUM_FILTERS; gi = gi + 1) begin : pack_out
            assign data_out_flat[gi*16 +: 16] = out_buf[gi];
        end
    endgenerate

    wire signed [15:0] current_val = data_in[window_idx + pool_idx];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= P_IDLE;
            window_idx  <= 8'd0;
            pool_idx    <= 8'd0;
            out_idx     <= 8'd0;
            current_max <= 16'h8000;
            done        <= 1'b0;
        end
        else begin
            done <= 1'b0;
            case (state)
                P_IDLE: begin
                    if (start) begin
                        window_idx  <= 8'd0;
                        pool_idx    <= 8'd0;
                        out_idx     <= 8'd0;
                        current_max <= 16'h8000;
                        state       <= P_POOL;
                    end
                end
                P_POOL: begin
                    if (current_val > current_max)
                        current_max <= current_val;
                    if (pool_idx == POOL_SIZE - 1) begin
                        pool_idx <= 8'd0;
                        state    <= P_NEXT;
                    end
                    else begin
                        pool_idx <= pool_idx + 1;
                    end
                end
                P_NEXT: begin
                    out_buf[out_idx] <= current_max;
                    out_idx          <= out_idx + 1;
                    current_max      <= 16'h8000;
                    window_idx       <= window_idx + STRIDE;
                    if (out_idx == OUTPUT_LEN - 1) begin
                        state <= P_DONE;
                    end
                    else begin
                        state <= P_POOL;
                    end
                end
                P_DONE: begin
                    done  <= 1'b1;
                    state <= P_IDLE;
                end
                default: state <= P_IDLE;
            endcase
        end
    end

endmodule
