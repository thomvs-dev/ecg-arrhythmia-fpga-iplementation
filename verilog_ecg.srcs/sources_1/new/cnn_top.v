`timescale 1ns / 1ps

module cnn_top (
    input  wire       clk,          // 100MHz system clock
    input  wire       rst_n,        // Active low reset
    input  wire [7:0] sample_in,    // Incoming ECG sample from bram_reader
    input  wire       sample_valid, // High for 1 clock when sample is ready
    output reg  [2:0] result,       // Classification result (0 to 4)
    output reg        result_valid  // High for 1 clock when result is ready
);

    // ─── Parameters ───────────────────────────────────────────────────
    parameter SIGNAL_LEN  = 186;    // Samples per ECG beat
    parameter CONV1_FILTERS = 32;   // Filters in conv layer 1
    parameter CONV1_KERNEL  = 5;    // Kernel size of conv layer 1
    parameter CONV2_FILTERS = 64;   // Filters in conv layer 2
    parameter CONV2_KERNEL  = 3;    // Kernel size of conv layer 2
    parameter CONV3_FILTERS = 128;   // Filters in conv layer 3
    parameter CONV3_KERNEL  = 3;    // Kernel size of conv layer 3
    parameter NUM_CLASSES   = 5;    // Output classes (0 to 4)

    // ─── FSM States ───────────────────────────────────────────────────
    localparam S_IDLE       = 4'd0;
    localparam S_COLLECT    = 4'd1;
    localparam S_CONV1      = 4'd2;
    localparam S_CONV2      = 4'd3;
    localparam S_CONV3      = 4'd4;
    localparam S_DENSE1     = 4'd5;
    localparam S_DENSE2     = 4'd6;
    localparam S_DENSE3     = 4'd7;
    localparam S_OUTPUT     = 4'd8;

    reg [3:0] state;

    // ─── Signal Buffer ────────────────────────────────────────────────
    reg signed [7:0] signal_buf [0:SIGNAL_LEN-1];
    reg [7:0]        sample_count;

    wire [SIGNAL_LEN*8-1:0] signal_buf_flat;
    genvar gs;
    generate
        for (gs = 0; gs < SIGNAL_LEN; gs = gs + 1) begin : pack_signal_buf
            assign signal_buf_flat[gs*8 +: 8] = signal_buf[gs];
        end
    endgenerate

    // ─── Layer Output Wires (flattened) ───────────────────────────────
    wire [CONV1_FILTERS*16-1:0] conv1_out_flat;
    wire                        conv1_done;

    wire [CONV2_FILTERS*16-1:0] conv2_out_flat;
    wire                        conv2_done;

    wire [CONV3_FILTERS*16-1:0] conv3_out_flat;
    wire                        conv3_done;

    wire [64*16-1:0]            dense1_out_flat;
    wire                        dense1_done;
    
    wire [32*16-1:0]            dense2_out_flat;
    wire                        dense2_done;

    wire [5*16-1:0]             dense3_out_flat;
    wire                        dense3_done;

    // ─── Layer Control Signals ────────────────────────────────────────
    reg conv1_start;

    // ─── Conv Layer 1 ─────────────────────────────────────────────────
    conv1d #(
        .INPUT_LEN    (SIGNAL_LEN),
        .KERNEL_SIZE  (CONV1_KERNEL),
        .NUM_FILTERS  (CONV1_FILTERS),
        .WEIGHT_FILE  ("conv1_weights.mem"),
        .BIAS_FILE    ("conv1_bias.mem")
    ) u_conv1 (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (conv1_start),
        .signal_in_flat (signal_buf_flat),
        .conv_out_flat  (conv1_out_flat),
        .done           (conv1_done)
    );

    wire [CONV1_FILTERS*16-1:0] pool1_out_flat;
    wire                        pool1_done;

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
        .WEIGHT_FILE  ("conv2_weights.mem"),
        .BIAS_FILE    ("conv2_bias.mem")
    ) u_conv2 (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (pool1_done),
        .signal_in_flat (pool1_out_flat[CONV1_FILTERS*8-1:0]),
        .conv_out_flat  (conv2_out_flat),
        .done           (conv2_done)
    );

    wire [CONV2_FILTERS*16-1:0] pool2_out_flat;
    wire                        pool2_done;

    maxpool #(
        .NUM_FILTERS  (CONV2_FILTERS),
        .POOL_SIZE    (3),
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
        .WEIGHT_FILE  ("conv3_weights.mem"),
        .BIAS_FILE    ("conv3_bias.mem")
    ) u_conv3 (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (pool2_done),
        .signal_in_flat (pool2_out_flat[CONV2_FILTERS*8-1:0]),
        .conv_out_flat  (conv3_out_flat),
        .done           (conv3_done)
    );

    wire [CONV3_FILTERS*16-1:0] pool3_out_flat;
    wire                        pool3_done;

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
    // 0-pad pool3 output (128 elements) to match the expected 2944 elements
    wire [(2944*16)-1:0] dense1_in_flat = { {(2944-128)*16{1'b0}}, pool3_out_flat };

    dense #(
        .INPUT_SIZE   (2944),
        .OUTPUT_SIZE  (64),
        .WEIGHT_FILE  ("dense1_weights.mem"),
        .BIAS_FILE    ("dense1_bias.mem")
    ) u_dense1 (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (pool3_done),
        .data_in_flat   (dense1_in_flat),
        .data_out_flat  (dense1_out_flat),
        .done           (dense1_done)
    );

    dense #(
        .INPUT_SIZE   (64),
        .OUTPUT_SIZE  (32),
        .WEIGHT_FILE  ("dense2_weights.mem"),
        .BIAS_FILE    ("dense2_bias.mem")
    ) u_dense2 (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (dense1_done),
        .data_in_flat   (dense1_out_flat),
        .data_out_flat  (dense2_out_flat),
        .done           (dense2_done)
    );

    dense #(
        .INPUT_SIZE   (32),
        .OUTPUT_SIZE  (5),
        .WEIGHT_FILE  ("dense3_weights.mem"),
        .BIAS_FILE    ("dense3_bias.mem")
    ) u_dense3 (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (dense2_done),
        .data_in_flat   (dense2_out_flat),
        .data_out_flat  (dense3_out_flat),
        .done           (dense3_done)
    );

    // ─── Unpack dense output for argmax ───────────────────────────────
    wire signed [15:0] dense_out [0:NUM_CLASSES-1];
    genvar gd;
    generate
        for (gd = 0; gd < NUM_CLASSES; gd = gd + 1) begin : unpack_dense_out
            assign dense_out[gd] = dense3_out_flat[gd*16 +: 16];
        end
    endgenerate

    // ─── FSM ──────────────────────────────────────────────────────────
    integer i;
    always @(posedge clk) begin
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
                    if (pool3_done) state <= S_DENSE1;
                end

                S_DENSE1: begin
                    if (dense1_done) state <= S_DENSE2;
                end

                S_DENSE2: begin
                    if (dense2_done) state <= S_DENSE3;
                end
                
                S_DENSE3: begin
                    if (dense3_done) state <= S_OUTPUT;
                end

                S_OUTPUT: begin
                    begin : argmax_block
                        reg signed [15:0] max_val;
                        reg [2:0]         max_idx;
                        integer           k;
                        max_val = dense_out[0];
                        max_idx = 3'd0;
                        for (k = 1; k < NUM_CLASSES; k = k + 1) begin
                            if (dense_out[k] > max_val) begin
                                max_val = dense_out[k];
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