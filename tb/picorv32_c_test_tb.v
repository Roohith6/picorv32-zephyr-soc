`timescale 1ns / 1ps

module picorv32_c_test_tb;

    localparam CLK_PERIOD   = 10;
    localparam CLKS_PER_BIT = 4;
    localparam BIT_PERIOD   = CLK_PERIOD * CLKS_PER_BIT;

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
        $readmemh("fw/c_test.hex", dut.ram.mem);
    end

    initial begin
        repeat (10) @(posedge clk);
        resetn = 1;
        $display("[%0t] resetn released", $time);
    end

    always @(posedge clk) begin
        if (resetn && trap) begin
            $display("[%0t] UNEXPECTED trap", $time);
            $display("C TEST: FAIL");
            $finish;
        end
    end

    // Decode a byte off the tx line the same way as before, but now
    // wrapped in a loop so it captures however many bytes come through.
    task decode_byte(output [7:0] result);
        integer i;
        begin
            @(negedge tx);
            #(BIT_PERIOD / 2);
            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_PERIOD);
                result[i] = tx;
            end
            #(BIT_PERIOD); // stop bit, not checked here for brevity
        end
    endtask

    reg [7:0] received [0:15];
    integer   n;

    initial begin
        for (n = 0; n < 2; n = n + 1) begin
            decode_byte(received[n]);
            $display("[%0t] Received byte %0d: 0x%02h ('%c')", $time, n, received[n], received[n]);
        end

        if (received[0] == 8'h48 && received[1] == 8'h69) begin
            // 0x48='H', 0x69='i'
            $display("C TEST: PASS -- received \"Hi\" correctly");
        end else begin
            $display("C TEST: FAIL -- expected \"Hi\", got 0x%02h 0x%02h", received[0], received[1]);
        end
        $finish;
    end

    initial begin
        #5000;
        $display("C TEST: FAIL (timeout)");
        $finish;
    end

endmodule
