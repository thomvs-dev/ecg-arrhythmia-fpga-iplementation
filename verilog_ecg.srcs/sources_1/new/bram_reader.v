`timescale 1ns / 1ps

module bram_reader (
    input  wire       clk,          // 100MHz system clock
    input  wire       rst_n,        // Active low reset
    output reg [7:0]  sample_out,   // ECG sample output (Int8)
    output reg        sample_valid, // High for 1 clock when sample is ready
    output reg        done          // High when all samples sent
);

    // ─── Parameters ───────────────────────────────────────────────────
    // 5 ECG samples × 187 values each = 935 total values in BRAM
    parameter TOTAL_SAMPLES = 930;
    
    // Controls how fast samples are fed to CNN
    // 100MHz clock / 1000 = one sample every 10 microseconds
    parameter SAMPLE_RATE_DIV = 1000;

    // ─── BRAM Declaration ─────────────────────────────────────────────
    // This is where your ecg_test_samples.mem gets loaded
    (* ram_style = "block" *)
    reg [7:0] bram [0:TOTAL_SAMPLES-1];

    // Initialize BRAM with your extracted ECG samples
    initial begin
        $readmemh("ecg_test_samples.mem", bram);
    end

    // ─── Internal Registers ───────────────────────────────────────────
    reg [9:0]  addr;          // BRAM address counter (0 to 934)
    reg [9:0]  clk_div;       // Clock divider counter
    reg        reading;       // High while actively reading samples

    // ─── Main Logic ───────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            addr         <= 10'd0;
            clk_div      <= 10'd0;
            sample_out   <= 8'd0;
            sample_valid <= 1'b0;
            done         <= 1'b0;
            reading      <= 1'b1;
        end
        else begin
            // Default - sample_valid is only high for 1 clock cycle
            sample_valid <= 1'b0;

            if (reading) begin
                if (clk_div == SAMPLE_RATE_DIV - 1) begin
                    clk_div      <= 10'd0;

                    // Read sample from BRAM and output it
                    sample_out   <= bram[addr];
                    sample_valid <= 1'b1;

                    // Advance address
                    if (addr == TOTAL_SAMPLES - 1) begin
                        addr    <= 10'd0;   // loop back to start
                        done    <= 1'b1;    // signal completion
                        reading <= 1'b0;    // stop reading
                    end
                    else begin
                        addr    <= addr + 1;
                        done    <= 1'b0;
                    end
                end
                else begin
                    clk_div <= clk_div + 1;
                end
            end
        end
    end

endmodule
