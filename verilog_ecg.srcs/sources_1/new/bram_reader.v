`timescale 1ns / 1ps

module bram_reader (
    input  wire       clk,          // 100MHz system clock
    input  wire       rst_n,        // Active low reset
    input  wire       next_beat,    // Pulse high to send next beat (from main)
    output reg [7:0]  sample_out,   // ECG sample output (Int8)
    output reg        sample_valid, // High for 1 clock when sample is ready
    output reg        done          // High when all samples sent
);

    // ─── Parameters ───────────────────────────────────────────────────
    parameter TOTAL_SAMPLES = 930;      // 5 beats × 186 samples
    parameter BEAT_LEN      = 186;      // Samples per beat
    parameter SAMPLE_RATE_DIV = 1000;   // One sample every 10μs

    // ─── BRAM Declaration ─────────────────────────────────────────────
    (* ram_style = "block" *)
    reg [7:0] bram [0:TOTAL_SAMPLES-1];

    initial begin
        $readmemh("ecg_test_samples.mem", bram);
    end

    // ─── Internal Registers ───────────────────────────────────────────
    reg [9:0]  addr;           // BRAM address counter
    reg [9:0]  clk_div;        // Clock divider counter
    reg [7:0]  beat_sample;    // Sample counter within current beat (0 to 185)
    reg        sending;        // High while sending a beat
    reg        waiting;        // High while waiting for CNN to finish

    // ─── Main Logic ───────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            addr         <= 10'd0;
            clk_div      <= 10'd0;
            beat_sample  <= 8'd0;
            sample_out   <= 8'd0;
            sample_valid <= 1'b0;
            done         <= 1'b0;
            sending      <= 1'b1;    // Start sending first beat immediately
            waiting      <= 1'b0;
        end
        else begin
            sample_valid <= 1'b0;

            if (sending) begin
                // Send samples at controlled rate
                if (clk_div == SAMPLE_RATE_DIV - 1) begin
                    clk_div      <= 10'd0;
                    sample_out   <= bram[addr];
                    sample_valid <= 1'b1;
                    addr         <= addr + 1;
                    beat_sample  <= beat_sample + 1;

                    // Finished one beat (186 samples)
                    if (beat_sample == BEAT_LEN - 1) begin
                        beat_sample <= 8'd0;
                        sending     <= 1'b0;

                        // Check if all beats sent
                        if (addr == TOTAL_SAMPLES - 1) begin
                            done <= 1'b1;
                        end
                        else begin
                            waiting <= 1'b1;  // Wait for CNN to finish
                        end
                    end
                end
                else begin
                    clk_div <= clk_div + 1;
                end
            end

            // Wait for CNN to finish, then send next beat
            if (waiting && next_beat) begin
                waiting <= 1'b0;
                sending <= 1'b1;
                clk_div <= 10'd0;
            end
        end
    end

endmodule
