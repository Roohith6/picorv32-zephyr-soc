// picorv32_timer.v
// Free-running 32-bit counter, native mem interface.
//
// Register map (offset from Timer base, see picorv32_addr_decoder.v):
//   0x0  TIMER_COUNT (read/write):
//        Read  -> current count (increments every clock cycle)
//        Write -> reloads the counter to the written value
//
// This is a readable/reloadable counter, NOT yet an interrupt-driving
// timer -- PicoRV32's ENABLE_IRQ is still off in picorv32_top.v.
// Wiring an actual interrupt (for a real scheduler tick) is a
// deliberately separate, larger step that belongs with the Zephyr
// port itself, not bundled into this pass.

module picorv32_timer (
    input  wire        clk,
    input  wire        resetn,

    input  wire        mem_valid,
    output reg          mem_ready,
    input  wire [31:0]  mem_addr,
    input  wire [31:0]  mem_wdata,
    input  wire [3:0]   mem_wstrb,
    output reg  [31:0]  mem_rdata,

    output reg  [31:0]  count
);

    always @(posedge clk) begin
        if (!resetn) begin
            mem_ready <= 1'b0;
            count     <= 32'b0;
        end else begin
            mem_ready <= 1'b0;
            count     <= count + 1'b1;   // free-running, increments every cycle

            if (mem_valid && !mem_ready) begin
                mem_ready <= 1'b1;

                if (mem_wstrb != 4'b0000) begin
                    count <= mem_wdata;   // reload -- overrides the +1 above
                end else begin
                    mem_rdata <= count;
                end
            end
        end
    end

endmodule
