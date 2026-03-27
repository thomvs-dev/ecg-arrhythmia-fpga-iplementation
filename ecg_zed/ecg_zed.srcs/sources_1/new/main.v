`timescale 1ns / 1ps

module main (
    input  wire clk,        // 100MHz system clock (ZedBoard GCLK)
    input  wire rst_n,      // Active low reset (ZedBoard BTN0)
    output wire uart_tx     // UART TX pin (ZedBoard JE1 or USB-UART)
);

    // ─── Internal Wires ───────────────────────────────────────────────

    // BRAM Reader → CNN
    wire [7:0]  ecg_sample;         // One ECG sample (Int8, unsigned view)
    wire        sample_valid;       // High for 1 clock when sample is ready
    wire        bram_done;          // High when all samples have been sent

    // CNN → UART
    wire [2:0]  cnn_result;         // Classification result (0 to 4)
    wire        cnn_done;           // High for 1 clock when CNN finishes

    // ─── Module Instantiations ────────────────────────────────────────

    // 1. BRAM Reader
    // Reads pre-loaded ECG samples and feeds them
    // one by one to the CNN at a controlled rate
    bram_reader u_bram_reader (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_out   (ecg_sample),
        .sample_valid (sample_valid),
        .done         (bram_done)
    );

    // 2. CNN Top
    // Collects 187 samples, runs Conv→ReLU→MaxPool→Dense
    // outputs a 3-bit class label when done
    cnn_top u_cnn_top (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_in    (ecg_sample),
        .sample_valid (sample_valid),
        .result       (cnn_result),
        .result_valid (cnn_done)
    );

    // 3. UART Display
    // Transmits classification result as
    // human readable text to PC terminal (PuTTY)
    uart_display u_uart_display (
        .clk          (clk),
        .rst_n        (rst_n),
        .class_in     (cnn_result),
        .send         (cnn_done),
        .uart_tx      (uart_tx)
    );

endmodule
