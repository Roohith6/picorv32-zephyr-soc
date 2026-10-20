// picorv32_uart_tx.v
// Transmit-only UART peripheral speaking PicoRV32's native memory
// interface directly (no AXI). Real 8N1 (8 data bits, no parity,
// 1 stop bit) bit-shifting transmitter -- not a simulation shortcut.
//
// Register map (offsets from UART base, see picorv32_addr_decoder.v):
//   0x0  TX_DATA   (write-only) : writing a byte starts transmitting it
//   0x4  TX_STATUS (read-only) : bit0 = tx_ready (1 = idle, safe to write)
//
// Firmware contract: poll TX_STATUS bit0 before writing TX_DATA. The
// hardware does NOT block or queue a write that arrives mid-transmission
// -- this matches how real UART peripherals behave, and keeps the
// hardware simple; enforcing it is the driver's job.
//
// CLKS_PER_BIT: real hardware would set this to
// (system_clock_freq_hz / baud_rate). Defaults low here (4) purely
// for fast simulation -- override with the real calculated value
// once this targets actual clocked hardware/FPGA timing, or bit
// timing will be wrong on real silicon.

module picorv32_uart_tx #(
    parameter CLKS_PER_BIT = 4
) (
    input  wire        clk,
    input  wire        resetn,

    input  wire        mem_valid,
    output reg          mem_ready,
    input  wire [31:0]  mem_addr,
    input  wire [31:0]  mem_wdata,
    input  wire [3:0]   mem_wstrb,
    output reg  [31:0]  mem_rdata,

    output reg          tx        // serial line, idles high
);

    localparam REG_TX_DATA   = 1'b0;
    localparam REG_TX_STATUS = 1'b1;

    wire reg_sel = mem_addr[2];   // 0 = TX_DATA, 1 = TX_STATUS

    // Transmit shift-register state machine
    localparam ST_IDLE  = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    reg [1:0]  tx_state;
    reg [7:0]  tx_shift;
    reg [2:0]  bit_index;
    reg [15:0] clk_count;

    wire tx_ready = (tx_state == ST_IDLE);

    always @(posedge clk) begin
        if (!resetn) begin
            tx_state  <= ST_IDLE;
            tx        <= 1'b1;     // idle high
            clk_count <= 0;
            bit_index <= 0;
        end else begin
            case (tx_state)
                ST_IDLE: begin
                    tx <= 1'b1;
                    // start transmission is kicked off from the mem
                    // write logic below (see tx_shift load)
                end

                ST_START: begin
                    tx <= 1'b0;   // start bit
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        tx_state  <= ST_DATA;
                        bit_index <= 0;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                ST_DATA: begin
                    tx <= tx_shift[0];
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        tx_shift  <= {1'b0, tx_shift[7:1]};
                        if (bit_index == 3'd7)
                            tx_state <= ST_STOP;
                        else
                            bit_index <= bit_index + 1;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                ST_STOP: begin
                    tx <= 1'b1;   // stop bit
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        tx_state  <= ST_IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
            endcase
        end
    end

    // Memory interface: 1-cycle-latency handshake, same convention
    // as picorv32_ram.v
    always @(posedge clk) begin
        if (!resetn) begin
            mem_ready <= 1'b0;
        end else begin
            mem_ready <= 1'b0;

            if (mem_valid && !mem_ready) begin
                mem_ready <= 1'b1;

                if (mem_wstrb != 4'b0000) begin
                    // Write
                    if (reg_sel == REG_TX_DATA && tx_ready) begin
                        tx_shift <= mem_wdata[7:0];
                        tx_state <= ST_START;
                    end
                    // Writes to TX_STATUS, or TX_DATA while busy,
                    // are silently accepted but have no effect --
                    // matches the documented firmware contract above.
                end else begin
                    // Read
                    case (reg_sel)
                        REG_TX_DATA:   mem_rdata <= 32'h0; // write-only, reads as 0
                        REG_TX_STATUS: mem_rdata <= {31'b0, tx_ready};
                    endcase
                end
            end
        end
    end

endmodule
