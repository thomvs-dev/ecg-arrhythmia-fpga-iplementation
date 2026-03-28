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
    parameter SIGNAL_LEN  = 187;    // Samples per ECG beat
    parameter CONV1_FILTERS = 64;   // Filters in conv layer 1
    parameter CONV1_KERNEL  = 6;    // Kernel size of conv layer 1
    parameter CONV2_FILTERS = 64;   // Filters in conv layer 2
    parameter CONV2_KERNEL  = 3;    // Kernel size of conv layer 2
    parameter CONV3_FILTERS = 64;   // Filters in conv layer 3
    parameter CONV3_KERNEL  = 3;    // Kernel size of conv layer 3
    parameter NUM_CLASSES   = 5;    // Output classes (0 to 4)

    // ─── FSM States ───────────────────────────────────────────────────
    // The CNN runs as a state machine
    // each stage waits for previous to finish
    localparam S_IDLE       = 3'd0; // Waiting for samples
    localparam S_COLLECT    = 3'd1; // Collecting 187 samples
    localparam S_CONV1      = 3'd2; // Running Conv layer 1
    localparam S_CONV2      = 3'd3; // Running Conv layer 2
    localparam S_CONV3      = 3'd4; // Running Conv layer 3
    localparam S_DENSE      = 3'd5; // Running Dense layers
    localparam S_OUTPUT     = 3'd6; // Outputting result

    reg [2:0] state;

    // ─── Signal Buffer ────────────────────────────────────────────────
    // Stores incoming 187 samples before processing
    reg signed [7:0] signal_buf [0:SIGNAL_LEN-1];
    reg [7:0]        sample_count;

    // ─── Layer Output Wires ───────────────────────────────────────────
    // Conv1 outputs
    wire signed [15:0] conv1_out [0:CONV1_FILTERS-1];
    wire               conv1_done;

    // Conv2 outputs
    wire signed [15:0] conv2_out [0:CONV2_FILTERS-1];
    wire               conv2_done;

    // Conv3 outputs
    wire signed [15:0] conv3_out [0:CONV3_FILTERS-1];
    wire               conv3_done;

    // Dense output
    wire signed [15:0] dense_out [0:NUM_CLASSES-1];
    wire               dense_done;

    // ─── Layer Control Signals ────────────────────────────────────────
    reg conv1_start, conv2_start, conv3_start, dense_start;

    // ─── Conv Layer 1 ─────────────────────────────────────────────────
    conv1d #(
        .INPUT_LEN    (SIGNAL_LEN),
        .KERNEL_SIZE  (CONV1_KERNEL),
        .NUM_FILTERS  (CONV1_FILTERS),
        .WEIGHT_FILE  ("conv1_weights.mem")
    ) u_conv1 (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (conv1_start),
        .signal_in    (signal_buf),
        .conv_out     (conv1_out),
        .done         (conv1_done)
    );

    // ─── ReLU + MaxPool after Conv1 ───────────────────────────────────
    wire signed [15:0] pool1_out [0:CONV1_FILTERS-1];
    wire               pool1_done;

    maxpool #(
        .NUM_FILTERS  (CONV1_FILTERS),
        .POOL_SIZE    (3),
        .STRIDE       (2)
    ) u_pool1 (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (conv1_done),
        .data_in      (conv1_out),
        .data_out     (pool1_out),
        .done         (pool1_done)
    );

    // ─── Conv Layer 2 ─────────────────────────────────────────────────
    conv1d #(
        .INPUT_LEN    (SIGNAL_LEN/2),
        .KERNEL_SIZE  (CONV2_KERNEL),
        .NUM_FILTERS  (CONV2_FILTERS),
        .WEIGHT_FILE  ("conv2_weights.mem")
    ) u_conv2 (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (pool1_done),
        .signal_in    (pool1_out),
        .conv_out     (conv2_out),
        .done         (conv2_done)
    );

    // ─── ReLU + MaxPool after Conv2 ───────────────────────────────────
    wire signed [15:0] pool2_out [0:CONV2_FILTERS-1];
    wire               pool2_done;

    maxpool #(
        .NUM_FILTERS  (CONV2_FILTERS),
        .POOL_SIZE    (2),
        .STRIDE       (2)
    ) u_pool2 (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (conv2_done),
        .data_in      (conv2_out),
        .data_out     (pool2_out),
        .done         (pool2_done)
    );

    // ─── Conv Layer 3 ─────────────────────────────────────────────────
    conv1d #(
        .INPUT_LEN    (SIGNAL_LEN/4),
        .KERNEL_SIZE  (CONV3_KERNEL),
        .NUM_FILTERS  (CONV3_FILTERS),
        .WEIGHT_FILE  ("conv3_weights.mem")
    ) u_conv3 (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (pool2_done),
        .signal_in    (pool2_out),
        .conv_out     (conv3_out),
        .done         (conv3_done)
    );

    // ─── ReLU + MaxPool after Conv3 ───────────────────────────────────
    wire signed [15:0] pool3_out [0:CONV3_FILTERS-1];
    wire               pool3_done;

    maxpool #(
        .NUM_FILTERS  (CONV3_FILTERS),
        .POOL_SIZE    (2),
        .STRIDE       (2)
    ) u_pool3 (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (conv3_done),
        .data_in      (conv3_out),
        .data_out     (pool3_out),
        .done         (pool3_done)
    );

    // ─── Dense Layers ─────────────────────────────────────────────────
    dense #(
        .INPUT_SIZE   (CONV3_FILTERS),
        .OUTPUT_SIZE  (NUM_CLASSES),
        .WEIGHT_FILE  ("dense_weights.mem")
    ) u_dense (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (pool3_done),
        .data_in      (pool3_out),
        .data_out     (dense_out),
        .done         (dense_done)
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

                // Wait for first sample to arrive
                S_IDLE: begin
                    if (sample_valid) begin
                        signal_buf[0] <= sample_in;
                        sample_count  <= 8'd1;
                        state         <= S_COLLECT;
                    end
                end

                // Collect all 187 samples into buffer
                S_COLLECT: begin
                    if (sample_valid) begin
                        signal_buf[sample_count] <= sample_in;
                        sample_count <= sample_count + 1;

                        // Once all 187 samples collected, start CNN
                        if (sample_count == SIGNAL_LEN - 1) begin
                            sample_count <= 8'd0;
                            conv1_start  <= 1'b1;
                            state        <= S_CONV1;
                        end
                    end
                end

                // Wait for Conv1 + Pool1 to finish
                S_CONV1: begin
                    if (pool1_done)
                        state <= S_CONV2;
                end

                // Wait for Conv2 + Pool2 to finish
                S_CONV2: begin
                    if (pool2_done)
                        state <= S_CONV3;
                end

                // Wait for Conv3 + Pool3 to finish
                S_CONV3: begin
                    if (pool3_done)
                        state <= S_DENSE;
                end

                // Wait for Dense to finish
                S_DENSE: begin
                    if (dense_done)
                        state <= S_OUTPUT;
                end

                // Find the class with highest score (Argmax)
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