`timescale 1ns / 1ps

module uart_display (
    input  wire       clk,          // 100MHz system clock
    input  wire       rst_n,        // Active low reset
    input  wire [2:0] class_in,     // Classification result (0 to 4)
    input  wire       send,         // High for 1 clock to trigger send
    output reg        uart_tx       // UART TX pin
);

    // ─── UART Parameters ──────────────────────────────────────────────
    // Baud rate = 115200
    // Clock = 100MHz
    // Clocks per bit = 100,000,000 / 115,200 = 868
    localparam CLKS_PER_BIT = 868;

    // ─── FSM States ───────────────────────────────────────────────────
    localparam U_IDLE       = 3'd0; // Waiting for send
    localparam U_LOAD       = 3'd1; // Load message into buffer
    localparam U_START_BIT  = 3'd2; // Send UART start bit
    localparam U_DATA_BITS  = 3'd3; // Send 8 data bits
    localparam U_STOP_BIT   = 3'd4; // Send UART stop bit
    localparam U_NEXT_BYTE  = 3'd5; // Move to next character
    localparam U_DONE       = 3'd6; // Message fully sent

    reg [2:0] state;

    // ─── Message Buffer ───────────────────────────────────────────────
    // Longest message is 30 characters
    // "Beat: SUPRAVENTRICULAR (1)\r\n"
    reg [7:0] msg_buf [0:29];       // Message character buffer
    reg [4:0] msg_len;              // Length of current message
    reg [4:0] char_idx;             // Current character being sent

    // ─── UART Bit Registers ───────────────────────────────────────────
    reg [7:0]  tx_byte;             // Current byte being transmitted
    reg [2:0]  bit_idx;             // Current bit being sent (0 to 7)
    reg [9:0]  clk_count;          // Clock counter for baud rate

    // ─── Class Label ROM ──────────────────────────────────────────────
    // Each class maps to a human readable message
    // Displayed on PuTTY terminal on your PC
    task load_message;
        input [2:0] class_num;
        begin
            case (class_num)
                3'd0: begin
                    // "Beat: NORMAL (0)\r\n"
                    msg_buf[0]  <= 8'h42; // B
                    msg_buf[1]  <= 8'h65; // e
                    msg_buf[2]  <= 8'h61; // a
                    msg_buf[3]  <= 8'h74; // t
                    msg_buf[4]  <= 8'h3A; // :
                    msg_buf[5]  <= 8'h20; // space
                    msg_buf[6]  <= 8'h4E; // N
                    msg_buf[7]  <= 8'h4F; // O
                    msg_buf[8]  <= 8'h52; // R
                    msg_buf[9]  <= 8'h4D; // M
                    msg_buf[10] <= 8'h41; // A
                    msg_buf[11] <= 8'h4C; // L
                    msg_buf[12] <= 8'h20; // space
                    msg_buf[13] <= 8'h28; // (
                    msg_buf[14] <= 8'h30; // 0
                    msg_buf[15] <= 8'h29; // )
                    msg_buf[16] <= 8'h0D; // \r
                    msg_buf[17] <= 8'h0A; // \n
                    msg_len     <= 5'd18;
                end
                3'd1: begin
                    // "Beat: SUPRAVENTRICULAR (1)\r\n"
                    msg_buf[0]  <= 8'h42; // B
                    msg_buf[1]  <= 8'h65; // e
                    msg_buf[2]  <= 8'h61; // a
                    msg_buf[3]  <= 8'h74; // t
                    msg_buf[4]  <= 8'h3A; // :
                    msg_buf[5]  <= 8'h20; // space
                    msg_buf[6]  <= 8'h53; // S
                    msg_buf[7]  <= 8'h55; // U
                    msg_buf[8]  <= 8'h50; // P
                    msg_buf[9]  <= 8'h52; // R
                    msg_buf[10] <= 8'h41; // A
                    msg_buf[11] <= 8'h56; // V
                    msg_buf[12] <= 8'h45; // E
                    msg_buf[13] <= 8'h4E; // N
                    msg_buf[14] <= 8'h54; // T
                    msg_buf[15] <= 8'h52; // R
                    msg_buf[16] <= 8'h49; // I
                    msg_buf[17] <= 8'h43; // C
                    msg_buf[18] <= 8'h55; // U
                    msg_buf[19] <= 8'h4C; // L
                    msg_buf[20] <= 8'h41; // A
                    msg_buf[21] <= 8'h52; // R
                    msg_buf[22] <= 8'h20; // space
                    msg_buf[23] <= 8'h28; // (
                    msg_buf[24] <= 8'h31; // 1
                    msg_buf[25] <= 8'h29; // )
                    msg_buf[26] <= 8'h0D; // \r
                    msg_buf[27] <= 8'h0A; // \n
                    msg_len     <= 5'd28;
                end
                3'd2: begin
                    // "Beat: VENTRICULAR (2)\r\n"
                    msg_buf[0]  <= 8'h42; // B
                    msg_buf[1]  <= 8'h65; // e
                    msg_buf[2]  <= 8'h61; // a
                    msg_buf[3]  <= 8'h74; // t
                    msg_buf[4]  <= 8'h3A; // :
                    msg_buf[5]  <= 8'h20; // space
                    msg_buf[6]  <= 8'h56; // V
                    msg_buf[7]  <= 8'h45; // E
                    msg_buf[8]  <= 8'h4E; // N
                    msg_buf[9]  <= 8'h54; // T
                    msg_buf[10] <= 8'h52; // R
                    msg_buf[11] <= 8'h49; // I
                    msg_buf[12] <= 8'h43; // C
                    msg_buf[13] <= 8'h55; // U
                    msg_buf[14] <= 8'h4C; // L
                    msg_buf[15] <= 8'h41; // A
                    msg_buf[16] <= 8'h52; // R
                    msg_buf[17] <= 8'h20; // space
                    msg_buf[18] <= 8'h28; // (
                    msg_buf[19] <= 8'h32; // 2
                    msg_buf[20] <= 8'h29; // )
                    msg_buf[21] <= 8'h0D; // \r
                    msg_buf[22] <= 8'h0A; // \n
                    msg_len     <= 5'd23;
                end
                3'd3: begin
                    // "Beat: FUSION (3)\r\n"
                    msg_buf[0]  <= 8'h42; // B
                    msg_buf[1]  <= 8'h65; // e
                    msg_buf[2]  <= 8'h61; // a
                    msg_buf[3]  <= 8'h74; // t
                    msg_buf[4]  <= 8'h3A; // :
                    msg_buf[5]  <= 8'h20; // space
                    msg_buf[6]  <= 8'h46; // F
                    msg_buf[7]  <= 8'h55; // U
                    msg_buf[8]  <= 8'h53; // S
                    msg_buf[9]  <= 8'h49; // I
                    msg_buf[10] <= 8'h4F; // O
                    msg_buf[11] <= 8'h4E; // N
                    msg_buf[12] <= 8'h20; // space
                    msg_buf[13] <= 8'h28; // (
                    msg_buf[14] <= 8'h33; // 3
                    msg_buf[15] <= 8'h29; // )
                    msg_buf[16] <= 8'h0D; // \r
                    msg_buf[17] <= 8'h0A; // \n
                    msg_len     <= 5'd18;
                end
                3'd4: begin
                    // "Beat: UNKNOWN (4)\r\n"
                    msg_buf[0]  <= 8'h42; // B
                    msg_buf[1]  <= 8'h65; // e
                    msg_buf[2]  <= 8'h61; // a
                    msg_buf[3]  <= 8'h74; // t
                    msg_buf[4]  <= 8'h3A; // :
                    msg_buf[5]  <= 8'h20; // space
                    msg_buf[6]  <= 8'h55; // U
                    msg_buf[7]  <= 8'h4E; // N
                    msg_buf[8]  <= 8'h4B; // K
                    msg_buf[9]  <= 8'h4E; // N
                    msg_buf[10] <= 8'h4F; // O
                    msg_buf[11] <= 8'h57; // W
                    msg_buf[12] <= 8'h4E; // N
                    msg_buf[13] <= 8'h20; // space
                    msg_buf[14] <= 8'h28; // (
                    msg_buf[15] <= 8'h34; // 4
                    msg_buf[16] <= 8'h29; // )
                    msg_buf[17] <= 8'h0D; // \r
                    msg_buf[18] <= 8'h0A; // \n
                    msg_len     <= 5'd19;
                end
                default: begin
                    msg_buf[0] <= 8'h3F; // ?
                    msg_buf[1] <= 8'h0D; // \r
                    msg_buf[2] <= 8'h0A; // \n
                    msg_len    <= 5'd3;
                end
            endcase
        end
    endtask

    // ─── Main FSM ─────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= U_IDLE;
            uart_tx  <= 1'b1;       // UART idle state is high
            char_idx <= 5'd0;
            bit_idx  <= 3'd0;
            clk_count<= 10'd0;
        end
        else begin
            case (state)

                // ── Wait for send signal ──────────────────────────────
                U_IDLE: begin
                    uart_tx  <= 1'b1;
                    char_idx <= 5'd0;
                    bit_idx  <= 3'd0;
                    clk_count<= 10'd0;
                    if (send) begin
                        state <= U_LOAD;
                    end
                end

                // ── Load message into buffer ──────────────────────────
                U_LOAD: begin
                    load_message(class_in);
                    char_idx <= 5'd0;
                    state    <= U_START_BIT;
                end

                // ── Send UART start bit (always 0) ────────────────────
                U_START_BIT: begin
                    uart_tx <= 1'b0;
                    tx_byte <= msg_buf[char_idx];

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 10'd0;
                        bit_idx   <= 3'd0;
                        state     <= U_DATA_BITS;
                    end
                    else begin
                        clk_count <= clk_count + 1;
                    end
                end

                // ── Send 8 data bits LSB first ────────────────────────
                U_DATA_BITS: begin
                    uart_tx <= tx_byte[bit_idx];

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 10'd0;

                        if (bit_idx == 3'd7) begin
                            state <= U_STOP_BIT;
                        end
                        else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                    else begin
                        clk_count <= clk_count + 1;
                    end
                end

                // ── Send UART stop bit (always 1) ─────────────────────
                U_STOP_BIT: begin
                    uart_tx <= 1'b1;

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 10'd0;
                        state     <= U_NEXT_BYTE;
                    end
                    else begin
                        clk_count <= clk_count + 1;
                    end
                end

                // ── Move to next character ────────────────────────────
                U_NEXT_BYTE: begin
                    if (char_idx == msg_len - 1) begin
                        state <= U_DONE;
                    end
                    else begin
                        char_idx <= char_idx + 1;
                        state    <= U_START_BIT;
                    end
                end

                // ── Message fully sent ────────────────────────────────
                U_DONE: begin
                    uart_tx <= 1'b1;
                    state   <= U_IDLE;
                end

                default: state <= U_IDLE;

            endcase
        end
    end

endmodule
