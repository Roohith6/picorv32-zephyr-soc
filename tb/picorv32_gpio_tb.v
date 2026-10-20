`timescale 1ns / 1ps

module picorv32_gpio_tb;

    reg clk = 0;
    reg resetn = 0;
    wire trap;
    wire tx;
    wire [7:0] gpio_out;

    always #5 clk = ~clk;

    picorv32_top dut (
        .clk      (clk),
        .resetn   (resetn),
        .trap     (trap),
        .tx       (tx),
        .gpio_out (gpio_out)
    );

    initial begin
        #1;
        $readmemh("fw/gpio_test.hex", dut.ram.mem);
    end

    initial begin
        repeat (10) @(posedge clk);
        resetn = 1;
        $display("[%0t] resetn released", $time);
    end

    always @(posedge clk) begin
        if (resetn && trap) begin
            $display("[%0t] UNEXPECTED trap", $time);
            $display("GPIO TEST: FAIL");
            $finish;
        end
    end

    // No bit-timing to decode here -- just wait long enough for the
    // program to execute, then look directly at the pins.
    initial begin
        #1000;
        if (gpio_out === 8'hAA) begin
            $display("[%0t] gpio_out = 0x%02h -- correct", $time, gpio_out);
            $display("GPIO TEST: PASS");
        end else begin
            $display("[%0t] gpio_out = 0x%02h -- expected 0xaa", $time, gpio_out);
            $display("GPIO TEST: FAIL");
        end
        $finish;
    end

endmodule
