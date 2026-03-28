`timescale 1ns / 1ps

module maxpool #(
    parameter NUM_FILTERS = 64,     // Number of input channels
    parameter POOL_SIZE   = 3,      // Pooling window size
    parameter STRIDE      = 2       // Stride of pooling window
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire signed [15:0]       data_in  [0:NUM_FILTERS-1],
    output reg  signed [15:0]       data_out [0:NUM_FILTERS-1],
    output reg                      done
);

    // ─── Parameters ───────────────────────────────────────────────────
    // Output length after pooling
    localparam OUTPUT_LEN = (NUM_FILTERS - POOL_SIZE) / STRIDE + 1;

    // ─── FSM States ───────────────────────────────────────────────────
    localparam P_IDLE    = 2'd0;    // Waiting for start
    localparam P_POOL    = 2'd1;    // Computing max in window
    localparam P_NEXT    = 2'd2;    // Moving to next window
    localparam P_DONE    = 2'd3;    // All windows computed

    reg [1:0] state;

    // ─── Internal Registers ───────────────────────────────────────────
    reg [7:0]        window_idx;    // Current window position
    reg [7:0]        pool_idx;      // Position inside current window
    reg signed [15:0] current_max; // Max value found so far in window
    reg [7:0]        out_idx;       // Output buffer index

    // ─── Output Buffer ────────────────────────────────────────────────
    reg signed [15:0] out_buf [0:OUTPUT_LEN-1];

    // ─── Current value being compared ─────────────────────────────────
    wire signed [15:0] current_val = data_in[window_idx + pool_idx];

    // ─── Main FSM ─────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= P_IDLE;
            window_idx  <= 8'd0;
            pool_idx    <= 8'd0;
            out_idx     <= 8'd0;
            current_max <= 16'h8000;    // Minimum signed 16bit value
            done        <= 1'b0;
        end
        else begin
            done <= 1'b0;

            case (state)

                // ── Wait for start ────────────────────────────────────
                P_IDLE: begin
                    if (start) begin
                        window_idx  <= 8'd0;
                        pool_idx    <= 8'd0;
                        out_idx     <= 8'd0;
                        current_max <= 16'h8000;
                        state       <= P_POOL;
                    end
                end

                // ── Find max in current window ────────────────────────
                P_POOL: begin
                    // Compare current value with running max
                    if (current_val > current_max)
                        current_max <= current_val;

                    if (pool_idx == POOL_SIZE - 1) begin
                        // Window complete — store max and move on
                        pool_idx <= 8'd0;
                        state    <= P_NEXT;
                    end
                    else begin
                        pool_idx <= pool_idx + 1;
                    end
                end

                // ── Store result, advance window ──────────────────────
                P_NEXT: begin
                    // Store max value of this window
                    out_buf[out_idx] <= current_max;
                    out_idx          <= out_idx + 1;

                    // Reset max for next window
                    current_max <= 16'h8000;

                    // Advance window by stride
                    window_idx <= window_idx + STRIDE;

                    if (out_idx == OUTPUT_LEN - 1) begin
                        // All windows done
                        data_out <= out_buf;
                        state    <= P_DONE;
                    end
                    else begin
                        state <= P_POOL;
                    end
                end

                // ── Done ──────────────────────────────────────────────
                P_DONE: begin
                    done  <= 1'b1;
                    state <= P_IDLE;
                end

                default: state <= P_IDLE;

            endcase
        end
    end

endmodule
```

---

**Key things to understand:**

**`16'h8000` is the minimum signed 16-bit value** — it's `-32768` in decimal. We initialize `current_max` to this so any real value from the CNN will always be larger on the first comparison, guaranteeing the max logic works correctly from the very first value.

**No weights needed** — `maxpool.v` has no `.mem` file because max pooling has no learnable parameters. It just finds the maximum value in each window — pure hardware logic.

**Stride handling** — the window advances by `STRIDE` positions each time, matching exactly how your Keras model was configured:
```
Pool1 → POOL_SIZE=3, STRIDE=2
Pool2 → POOL_SIZE=2, STRIDE=2
Pool3 → POOL_SIZE=2, STRIDE=2
```

**ReLU already applied** — by the time data reaches `maxpool.v` it has already been ReLU'd inside `conv1d.v`, so no activation needed here.

---

**Your module count so far:**
```
main.v          ✅
bram_reader.v   ✅
cnn_top.v       ✅
conv1d.v        ✅
maxpool.v       ✅
dense.v         ← next
uart_display.v  ← last