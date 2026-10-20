// picorv32_ram.v
// Minimal single-port RAM speaking PicoRV32's native mem_valid/mem_ready
// interface directly. Stage A: no AXI4-Lite involved.
//
// Latency: 1 cycle (mem_valid this cycle -> mem_ready next cycle).
// Depth:   WORDS x 32-bit words (default 2048 words = 8KB).

module picorv32_ram #(
    parameter WORDS = 2048
) (
    input  wire        clk,
    input  wire         mem_valid,
    output reg          mem_ready,
    input  wire [3:0]   mem_wstrb,
    input  wire [31:0]  mem_addr,
    input  wire [31:0]  mem_wdata,
    output reg  [31:0]  mem_rdata
);

    // Word-addressed storage: mem_addr[31:2] selects the word,
    // low 2 address bits (byte offset within word) are unused here
    // since accesses are always word-sized on this simple model.
    reg [31:0] mem [0:WORDS-1];

    // NOTE: Verilog does NOT zero-initialize arrays by default --
    // without this block, `mem` starts as 'x' (unknown) in simulation,
    // which silently breaks decode logic downstream (looks like nothing
    // is happening, when actually every read is returning 'x'). Real
    // hardware BRAM is similarly undefined at power-on unless loaded
    // from an init file -- this block is a simulation convenience, and
    // will later be replaced/extended with $readmemh to load an actual
    // program image.
    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 32'h0;
    end

    // Index derived from address: adjust the slice width if you
    // change WORDS to something other than a power of two multiple.
    wire [$clog2(WORDS)-1:0] word_index = mem_addr[$clog2(WORDS)+1:2];

    always @(posedge clk) begin
        mem_ready <= 1'b0;

        if (mem_valid && !mem_ready) begin
            mem_ready <= 1'b1;

            // Byte-wise write, gated by mem_wstrb
            if (mem_wstrb[0]) mem[word_index][7:0]   <= mem_wdata[7:0];
            if (mem_wstrb[1]) mem[word_index][15:8]  <= mem_wdata[15:8];
            if (mem_wstrb[2]) mem[word_index][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) mem[word_index][31:24] <= mem_wdata[31:24];

            // Read always returns the pre-write value this cycle
            // (fine for now: PicoRV32 never reads and writes the
            // same address in the same access).
            mem_rdata <= mem[word_index];
        end
    end

endmodule
