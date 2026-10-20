`timescale 1ns / 1ps

module picorv32_program_tb;

    reg clk = 0;
    reg resetn = 0;
    wire trap;

    always #5 clk = ~clk;

    picorv32_top dut (
        .clk    (clk),
        .resetn (resetn),
        .trap   (trap)
    );

    // Load the compiled test program into RAM before reset releases.
    // The #1 delay ensures this runs AFTER picorv32_ram's own
    // zero-init initial block (both are `initial` blocks scheduled
    // at time 0; the delay guarantees ordering rather than relying
    // on simulator elaboration order).
    initial begin
        #1;
        $readmemh("fw/test.hex", dut.ram.mem);
    end

    initial begin
        repeat (10) @(posedge clk);
        resetn = 1;
        $display("[%0t] resetn released", $time);
    end

    always @(posedge clk) begin
        if (resetn && trap) begin
            $display("[%0t] UNEXPECTED trap -- program should not trap", $time);
            $display("PROGRAM TEST: FAIL");
            $finish;
        end
    end

    // Give the program plenty of cycles to execute the 4 real
    // instructions (each may take several clock cycles on PicoRV32's
    // multi-cycle pipeline) before checking the result.
    initial begin
        #1000;
        if (dut.ram.mem[64] === 32'hCAFEBABE) begin
            // address 0x100 / 4 = word index 64
            $display("[%0t] mem[0x100] = %h -- store confirmed correct", $time, dut.ram.mem[64]);
            $display("PROGRAM TEST: PASS");
        end else begin
            $display("[%0t] mem[0x100] = %h -- expected cafebabe", $time, dut.ram.mem[64]);
            $display("PROGRAM TEST: FAIL");
        end
        $finish;
    end

endmodule
