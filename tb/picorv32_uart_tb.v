`timescale 1ns / 1ps

module picorv32_uart_tb;

    localparam CLK_PERIOD    = 10;   // ns, matches "always #5 clk = ~clk"
    localparam CLKS_PER_BIT  = 4;    // must match picorv32_uart_tx's parameter
    localparam BIT_PERIOD    = CLK_PERIOD * CLKS_PER_BIT;

    reg clk = 0;
    reg resetn = 0;
    wire trap;
    wire tx;

    always #5 clk = ~clk;

    picorv32_top dut (
        .clk    (clk),
        .resetn (resetn),
        .trap   (trap),
        .tx     (tx)
    );

    initial begin
        #1;
        $readmemh("fw/uart_test.hex", dut.ram.mem);
    end

    initial begin
        repeat (10) @(posedge clk);
        resetn = 1;
        $display("[%0t] resetn released", $time);
    end

    always @(posedge clk) begin
        if (resetn && trap) begin
            $display("[%0t] UNEXPECTED trap", $time);
            $display("UART TEST: FAIL");
            $finish;
        end
    end

    // Serial line decoder: waits for the start bit (falling edge on
    // tx), then samples the MIDDLE of each following bit period --
    // sampling mid-bit rather than at the edge is standard UART RX
    // practice, since it's the point furthest from any edge jitter.
    reg [7:0] rx_byte;
    integer   i;
    reg       rx_done = 0;

    initial begin
        @(negedge tx);                      // start bit begins
        #(BIT_PERIOD / 2);                  // move to center of start bit
        if (tx !== 1'b0) begin
            $display("[%0t] ERROR: expected start bit low, got %b", $time, tx);
        end

        for (i = 0; i < 8; i = i + 1) begin
            #(BIT_PERIOD);                  // advance to center of next bit
            rx_byte[i] = tx;                // LSB first, matches tx_shift[0] first out
        end

        #(BIT_PERIOD);                      // advance to center of stop bit
        if (tx !== 1'b1) begin
            $display("[%0t] ERROR: expected stop bit high, got %b", $time, tx);
        end

        rx_done = 1;
        $display("[%0t] Decoded byte: 0x%02h", $time, rx_byte);

        if (rx_byte === 8'h41) begin
            $display("UART TEST: PASS");
        end else begin
            $display("[%0t] expected 0x41, got 0x%02h", $time, rx_byte);
            $display("UART TEST: FAIL");
        end
        $finish;
    end

    // Safety timeout in case tx never toggles at all
    initial begin
        #5000;
        if (!rx_done) begin
            $display("[%0t] TIMEOUT -- tx line never showed a start bit", $time);
            $display("UART TEST: FAIL");
            $finish;
        end
    end

endmodule
