`timescale 1ns / 1ps

module cnn_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] sample_in,
    input  wire       sample_valid,
    output reg  [2:0] result,
    output reg        result_valid
);

    // ─── Parameters ───────────────────────────────────────────────────
    parameter SIGNAL_LEN    = 187;
    parameter CONV1_FILTERS = 64;
    parameter CONV1_KERNEL  = 6;
    parameter CONV2_FILTERS = 64;
    parameter CONV2_KERNEL  = 3;
    parameter CONV3_FILTERS = 64;
    parameter CONV3_KERNEL  = 3;
    parameter NUM_CLASSES   = 5;

    // ─── FSM States ───────────────────────────────────────────────────
    localparam S_IDLE    = 3'd0;
    localparam S_COLLECT = 3'd1;
    localparam S_CONV1   = 3'd2;
    localparam S_CONV2   = 3'd3;
    localparam S_CONV3   = 3'd4;
    localparam S_DENSE   = 3'd5;
    localparam S_OUTPUT  = 3'd6;
    reg [2:0] state;

    // ─── Signal Buffer ────────────────────────────────────────────────
    reg signed [7:0] signal_buf [0:SIGNAL_LEN-1];
    reg [7:0]        sample_count;

    // ─── Pack signal_buf into flat vector for conv1 ───────────────────
    wire [8*SIGNAL_LEN-1:0] signal_buf_flat;
    genvar gi;
    generate
        for (gi = 0; gi < SIGNAL_LEN; gi = gi + 1) begin : pack_sig
            assign signal_buf_flat[gi*8 +: 8] = signal_buf[gi];
        end
    endgenerate

    // ─── Layer Output Wires (flat packed) ─────────────────────────────
    wire [16*CONV1_FILTERS-1:0] conv1_out_flat;
    wire                        conv1_done;
    wire [16*CONV1_FILTERS-1:0] pool1_out_flat;
    wire                        pool1_done;
    wire [16*CONV2_FILTERS-1:0] conv2_out_flat;
    wire                        conv2_done;
    wire [16*CONV2_FILTERS-1:0] pool2_out_flat;
    wire                        pool2_done;
    wire [16*CONV3_FILTERS-1:0] conv3_out_flat;
    wire                        conv3_done;
    wire [16*CONV3_FILTERS-1:0] pool3_out_flat;
    wire                        pool3_done;
    wire [16*NUM_CLASSES-1:0]   dense_out_flat;
    wire                        dense_done;

    // ─── Layer Control Signals ────────────────────────────────────────
    reg conv1_start, conv2_start, conv3_start, dense_start;

    // ─── Conv Layer 1 ─────────────────────────────────────────────────
    conv1d #(
        .INPUT_LEN    (SIGNAL_LEN),
        .KERNEL_SIZE  (CONV1_KERNEL),
        .NUM_FILTERS  (CONV1_FILTERS),
        .WEIGHT_FILE  ("conv1_weights.mem")
    ) u_conv1 (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (conv1_start),
        .signal_in_flat  (signal_buf_flat),
        .conv_out_flat   (conv1_out_flat),
        .done            (conv1_done)
    );

    // ─── ReLU + MaxPool after Conv1 ───────────────────────────────────
    maxpool #(
        .NUM_FILTERS  (CONV1_FILTERS),
        .POOL_SIZE    (3),
        .STRIDE       (2)
    ) u_pool1 (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (conv1_done),
        .data_in_flat   (conv1_out_flat),
        .data_out_flat  (pool1_out_flat),
        .done           (pool1_done)
    );

    // ─── Conv Layer 2 ─────────────────────────────────────────────────
    conv1d #(
        .INPUT_LEN    (CONV1_FILTERS),
        .KERNEL_SIZE  (CONV2_KERNEL),
        .NUM_FILTERS  (CONV2_FILTERS),
        .WEIGHT_FILE  ("conv2_weights.mem")
    ) u_conv2 (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (pool1_done),
        .signal_in_flat  (pool1_out_flat[8*CONV1_FILTERS-1:0]),
        .conv_out_flat   (conv2_out_flat),
        .done            (conv2_done)
    );

    // ─── ReLU + MaxPool after Conv2 ───────────────────────────────────
    maxpool #(
        .NUM_FILTERS  (CONV2_FILTERS),
        .POOL_SIZE    (2),
        .STRIDE       (2)
    ) u_pool2 (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (conv2_done),
        .data_in_flat   (conv2_out_flat),
        .data_out_flat  (pool2_out_flat),
        .done           (pool2_done)
    );

    // ─── Conv Layer 3 ─────────────────────────────────────────────────
    conv1d #(
        .INPUT_LEN    (CONV2_FILTERS),
        .KERNEL_SIZE  (CONV3_KERNEL),
        .NUM_FILTERS  (CONV3_FILTERS),
        .WEIGHT_FILE  ("conv3_weights.mem")
    ) u_conv3 (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (pool2_done),
        .signal_in_flat  (pool2_out_flat[8*CONV2_FILTERS-1:0]),
        .conv_out_flat   (conv3_out_flat),
        .done            (conv3_done)
    );

    // ─── ReLU + MaxPool after Conv3 ───────────────────────────────────
    maxpool #(
        .NUM_FILTERS  (CONV3_FILTERS),
        .POOL_SIZE    (2),
        .STRIDE       (2)
    ) u_pool3 (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (conv3_done),
        .data_in_flat   (conv3_out_flat),
        .data_out_flat  (pool3_out_flat),
        .done           (pool3_done)
    );

    // ─── Dense Layers ─────────────────────────────────────────────────
    dense #(
        .INPUT_SIZE   (CONV3_FILTERS),
        .OUTPUT_SIZE  (NUM_CLASSES),
        .WEIGHT_FILE  ("dense_weights.mem")
    ) u_dense (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (pool3_done),
        .data_in_flat   (pool3_out_flat),
        .data_out_flat  (dense_out_flat),
        .done           (dense_done)
    );

    // ─── FSM ──────────────────────────────────────────────────────────
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            sample_count <= 8'd0;
            result       <= 3'd0;
            result_valid <= 1'b0;
            conv1_start  <= 1'b0;
        end
        else begin
            result_valid <= 1'b0;
            conv1_start  <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (sample_valid) begin
                        signal_buf[0] <= sample_in;
                        sample_count  <= 8'd1;
                        state         <= S_COLLECT;
                    end
                end
                S_COLLECT: begin
                    if (sample_valid) begin
                        signal_buf[sample_count] <= sample_in;
                        sample_count <= sample_count + 1;
                        if (sample_count == SIGNAL_LEN - 1) begin
                            sample_count <= 8'd0;
                            conv1_start  <= 1'b1;
                            state        <= S_CONV1;
                        end
                    end
                end
                S_CONV1: begin
                    if (pool1_done) state <= S_CONV2;
                end
                S_CONV2: begin
                    if (pool2_done) state <= S_CONV3;
                end
                S_CONV3: begin
                    if (pool3_done) state <= S_DENSE;
                end
                S_DENSE: begin
                    if (dense_done) state <= S_OUTPUT;
                end
                S_OUTPUT: begin
                    begin : argmax_block
                        reg signed [15:0] max_val;
                        reg [2:0]         max_idx;
                        integer           k;
                        max_val = $signed(dense_out_flat[0 +: 16]);
                        max_idx = 3'd0;
                        for (k = 1; k < NUM_CLASSES; k = k + 1) begin
                            if ($signed(dense_out_flat[k*16 +: 16]) > max_val) begin
                                max_val = $signed(dense_out_flat[k*16 +: 16]);
                                max_idx = k[2:0];
                            end
                        end
                        result       <= max_idx;
                        result_valid <= 1'b1;
                    end
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule