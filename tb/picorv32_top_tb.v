// picorv32_top_tb.v
// Stage A smoke test: with RAM left at default (all zeros), the first
// fetch from address 0 is 0x00000000, which is not a valid RV32I
// instruction. PicoRV32 should detect this (CATCH_ILLINSN=1 default)
// and assert `trap`. This confirms reset sequencing, clocking, and the
// CPU<->RAM mem_valid/mem_ready handshake are all working -- before any
// real firmware is involved.

`timescale 1ns / 1ps

module picorv32_top_tb;

    reg clk = 0;
    reg resetn = 0;
    wire trap;

    // 100 MHz-equivalent clock for simulation purposes (period doesn't
    // need to match real hardware timing for a functional sim)
    always #5 clk = ~clk;

    picorv32_top dut (
        .clk    (clk),
        .resetn (resetn),
        .trap   (trap)
    );

    initial begin
        $dumpfile("picorv32_top_tb.vcd");
        $dumpvars(0, picorv32_top_tb);

        // Hold reset low for 10 clock edges, then release
        repeat (10) @(posedge clk);
        resetn = 1;
        $display("[%0t] resetn released, CPU should start fetching from 0x00000000", $time);
    end

    // Watch for the expected trap
    always @(posedge clk) begin
        if (resetn && trap) begin
            $display("[%0t] trap asserted -- illegal instruction correctly detected at reset vector", $time);
            $display("STAGE A SMOKE TEST: PASS");
            $finish;
        end
    end

    // Safety timeout: if trap never asserts, something's stuck
    // (e.g. mem_ready handshake not completing) -- fail loudly
    // instead of hanging the simulator indefinitely.
    initial begin
        #2000;
        $display("[%0t] TIMEOUT -- trap never asserted, check mem_valid/mem_ready handshake", $time);
        $display("STAGE A SMOKE TEST: FAIL");
        $finish;
    end

endmodule
