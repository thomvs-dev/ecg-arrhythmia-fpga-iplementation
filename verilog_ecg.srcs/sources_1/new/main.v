`timescale 1ns / 1ps

module main (
    input  wire clk,        // 100MHz system clock (ZedBoard GCLK)
    input  wire rst_btn,    // BTNC — press to RESET (active high button)
    input  wire btn_next,   // BTNU — press to cycle through results
    output wire uart_tx,    // UART TX pin (PMOD JE1 for external adapter)
    output wire [7:0] led   // 8 onboard LEDs for visual output
);

    // ─── Reset Inversion ──────────────────────────────────────────────
    // ZedBoard buttons are active-HIGH (1 when pressed, 0 when released)
    // Our modules use active-LOW reset (rst_n)
    // So: button NOT pressed → rst_n=1 → system RUNS
    //     button PRESSED     → rst_n=0 → system RESETS
    wire rst_n = ~rst_btn;

    // ─── Internal Wires ───────────────────────────────────────────────

    // BRAM Reader → CNN
    wire [7:0]  ecg_sample;
    wire        sample_valid;
    wire        bram_done;

    // CNN → Output
    wire [2:0]  cnn_result;
    wire        cnn_done;

    // ─── Store All 5 Results ──────────────────────────────────────────
    reg [2:0] results [0:4];
    reg [2:0] result_count;
    reg [2:0] display_idx;

    // ─── Button Debounce for btn_next ─────────────────────────────────
    reg [19:0] debounce_counter;
    reg        btn_prev;
    reg        btn_pressed;

    always @(posedge clk) begin
        if (!rst_n) begin
            debounce_counter <= 20'd0;
            btn_prev         <= 1'b0;
            btn_pressed      <= 1'b0;
        end
        else begin
            btn_pressed <= 1'b0;
            if (debounce_counter > 0) begin
                debounce_counter <= debounce_counter - 1;
            end
            else begin
                if (btn_next && !btn_prev) begin
                    btn_pressed      <= 1'b1;
                    debounce_counter <= 20'hFFFFF;
                end
                btn_prev <= btn_next;
            end
        end
    end

    // ─── Result Capture & Display Logic ───────────────────────────────
    reg [24:0] heartbeat_counter;

    // ─── Class Change Detection ─────────────────────────────────────
    reg [2:0]  prev_class;
    reg [24:0] blink_timer;

    always @(posedge clk) begin
        if (!rst_n) begin
            result_count      <= 3'd0;
            display_idx       <= 3'd0;
            heartbeat_counter <= 25'd0;
            prev_class        <= 3'd0;
            blink_timer       <= 25'd0;
            results[0] <= 3'd0;
            results[1] <= 3'd0;
            results[2] <= 3'd0;
            results[3] <= 3'd0;
            results[4] <= 3'd0;
        end
        else begin
            heartbeat_counter <= heartbeat_counter + 1;

            // Tick down the blink timer
            if (blink_timer > 0)
                blink_timer <= blink_timer - 1;

            // Capture each CNN result as it arrives
            if (cnn_done && result_count < 5) begin
                results[result_count] <= cnn_result;
                result_count          <= result_count + 1;
                display_idx           <= result_count;

                // Blink if this result differs from previous
                if (result_count == 0 || cnn_result != prev_class) begin
                    blink_timer <= 25'd25_000_000;
                end
                prev_class <= cnn_result;
            end

            // Button press cycles through stored results
            if (btn_pressed && result_count > 0) begin
                if (display_idx == result_count - 1)
                    display_idx <= 3'd0;
                else
                    display_idx <= display_idx + 1;

                // Blink if switching to a different class
                begin : check_change
                    reg [2:0] next_idx;
                    if (display_idx == result_count - 1)
                        next_idx = 3'd0;
                    else
                        next_idx = display_idx + 1;

                    if (results[next_idx] != results[display_idx])
                        blink_timer <= 25'd25_000_000;
                end
            end
        end
    end

    // ─── LED Assignments ──────────────────────────────────────────────
    // LED[2:0] = current displayed class result (binary 0–4)
    // LED[5:3] = which beat is being displayed (1–5 in binary)
    // LED[6]   = blinks for 0.5s when class changes
    // LED[7]   = heartbeat blink (~3Hz, proves design is alive)

    assign led[2:0] = results[display_idx];
    assign led[5:3] = display_idx + 1;
    assign led[6]   = (blink_timer > 0);
    assign led[7]   = heartbeat_counter[24];

    // ─── Module Instantiations ────────────────────────────────────────

    bram_reader u_bram_reader (
        .clk          (clk),
        .rst_n        (rst_n),
        .next_beat    (cnn_done),
        .sample_out   (ecg_sample),
        .sample_valid (sample_valid),
        .done         (bram_done)
    );

    cnn_top u_cnn_top (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_in    (ecg_sample),
        .sample_valid (sample_valid),
        .result       (cnn_result),
        .result_valid (cnn_done)
    );

    uart_display u_uart_display (
        .clk          (clk),
        .rst_n        (rst_n),
        .class_in     (cnn_result),
        .send         (cnn_done),
        .uart_tx      (uart_tx)
    );

endmodule