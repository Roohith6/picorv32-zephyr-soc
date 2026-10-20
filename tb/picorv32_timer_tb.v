`timescale 1ns / 1ps

module picorv32_timer_tb;

    reg clk = 0;
    reg resetn = 0;
    wire trap;
    wire tx;
    wire [7:0] gpio_out;
    wire [31:0] timer_out;

    always #5 clk = ~clk;

    picorv32_top dut (
        .clk       (clk),
        .resetn    (resetn),
        .trap      (trap),
        .tx        (tx),
        .gpio_out  (gpio_out),
        .timer_out (timer_out)
    );

    initial begin
        #1;
        $readmemh("fw/timer_test.hex", dut.ram.mem);
    end

    initial begin
        repeat (10) @(posedge clk);
        resetn = 1;
        $display("[%0t] resetn released", $time);
    end

    always @(posedge clk) begin
        if (resetn && trap) begin
            $display("[%0t] UNEXPECTED trap", $time);
            $display("TIMER TEST: FAIL");
            $finish;
        end
    end

    initial begin
        #50000;   // give the program plenty of time to run the delay loop
        if (dut.ram.mem[64] !== dut.ram.mem[65] && dut.ram.mem[65] > dut.ram.mem[64]) begin
            $display("[%0t] t0=%0d t1=%0d -- counter advanced correctly",
                $time, dut.ram.mem[64], dut.ram.mem[65]);
            $display("TIMER TEST: PASS");
        end else begin
            $display("[%0t] t0=%0d t1=%0d -- counter did NOT advance as expected",
                $time, dut.ram.mem[64], dut.ram.mem[65]);
            $display("TIMER TEST: FAIL");
        end
        $finish;
    end

endmodule
