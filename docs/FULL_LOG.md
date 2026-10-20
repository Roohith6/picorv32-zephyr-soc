# Complete Project Report — PicoRV32 SoC + Zephyr Port

Full conversation-order record: every step taken, every file created (with
full code), every error encountered, and how each was resolved, up to the
current point (mid-way through diagnosing PicoRV32's CSR/Zicsr limitation
for the Zephyr port).

---

# PART 1 — Environment Setup

## Decision: WSL2 Ubuntu over VirtualBox

Started on a VirtualBox Ubuntu VM (used for Cadence/OpenROAD via college
lab access separately). Moved to WSL2 Ubuntu for this project specifically
because:
- Near-native performance vs VirtualBox's virtualization overhead
- Better (though still imperfect) USB/JTAG passthrough for future FPGA work
- All required tools (Icarus Verilog, Yosys, RISC-V toolchain, Zephyr SDK)
  are Linux-native and install identically to VirtualBox Ubuntu

## Toolchain installed

- `build-essential`, `git`, `cmake`, `ninja-build`, etc. (base tools)
- `iverilog`, `gtkwave`, `yosys` (RTL simulation/synthesis)
- RISC-V GCC toolchain (via Zephyr SDK, `riscv64-zephyr-elf-*`)
- `west` (Zephyr's build tool) — installed inside a Python venv
  (`~/zephyrproject-venv`) after hitting Ubuntu 24.04's
  "externally-managed-environment" restriction (PEP 668)
- Zephyr SDK 1.0.1 (`~/zephyr-sdk-1.0.1`) — note: release format changed at
  v1.0.0 to "minimal" vs "gnu" bundles; the first download attempt at a
  guessed version number 404'd, corrected once the real releases page was
  checked

## ERROR 1 — `pip install --user west` → externally-managed-environment
**Fix:** created a dedicated venv (`python3 -m venv ~/zephyrproject-venv`),
activated it, installed `west` inside it. Added a `zenv` bash alias for
quick reactivation each session.

## ERROR 2 — Zephyr SDK download 404
**Cause:** guessed an old version number/filename format; SDK releases
≥v1.0.0 use `_minimal` or `_gnu` suffixed tarballs, not the old single
combined archive name.
**Fix:** found the real releases page, used the correct filename for
v1.0.1, selected the "minimal" bundle during `setup.sh`.

## ERROR 3 — `ModuleNotFoundError: No module named 'jsonschema'` during first `west build`
**Cause:** `pip install -r zephyr/scripts/requirements.txt` had been run in
a terminal session that was later closed before finishing, or the install
silently didn't complete inside the venv.
**Fix:** re-ran the requirements install inside the reactivated venv.

## ERROR 4 — `pkg-config package 'libusb-1.0 >= 1.0.9' not found` (during full requirements.txt install)
**Cause:** the full `requirements.txt` pulls in `hidapi` (via `spsdk`, an
NXP flashing tool) which needs a native `libusb` dev package not installed,
and isn't needed for this project (no NXP hardware).
**Fix:** installed only `requirements-base.txt` + `requirements-build-test.txt`
instead of the full file, skipping the unneeded flashing-tool dependencies.

## First toolchain verification
```bash
cd ~/zephyrproject
west build -b qemu_riscv32 zephyr/samples/hello_world -t run
```
Result: `Hello World! qemu_riscv32/qemu_virt_riscv32` printed correctly —
confirmed west, the Zephyr SDK, the Python deps, and the Zephyr source tree
all work together before touching any custom hardware.

---

# PART 2 — Stage A: PicoRV32 SoC in RTL

Project structure: `/mnt/e/picorv32-zephyr-soc/` with `rtl/`, `fw/`, `tb/`
subfolders.

## 2.1 — The CPU

`picorv32.v` — downloaded directly from YosysHQ's GitHub
(`https://raw.githubusercontent.com/YosysHQ/picorv32/master/picorv32.v`),
not authored. 3049 lines, not reproduced here since it's an unmodified
third-party file — same command reproduces it exactly.

## 2.2 — RAM

#### `picorv32_ram.v`
Final version, including the zero-init fix (see Error 5 below).

```verilog
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

    reg [31:0] mem [0:WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 32'h0;
    end

    wire [$clog2(WORDS)-1:0] word_index = mem_addr[$clog2(WORDS)+1:2];

    always @(posedge clk) begin
        mem_ready <= 1'b0;

        if (mem_valid && !mem_ready) begin
            mem_ready <= 1'b1;

            if (mem_wstrb[0]) mem[word_index][7:0]   <= mem_wdata[7:0];
            if (mem_wstrb[1]) mem[word_index][15:8]  <= mem_wdata[15:8];
            if (mem_wstrb[2]) mem[word_index][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) mem[word_index][31:24] <= mem_wdata[31:24];

            mem_rdata <= mem[word_index];
        end
    end

endmodule

```

## ERROR 5 — Simulation timeout, `mem_rdata_q` stuck at `xxxxxxxx`
**Symptom:** first smoke test (Section 2.4) timed out instead of tripping
the expected trap.
**Cause:** Verilog does NOT zero-initialize arrays by default in
simulation — a freshly-declared `reg [31:0] mem [0:WORDS-1]` starts as
unknown (`x`), not zero. The CPU's first fetch read `x` instead of
`0x00000000`, so the illegal-instruction check itself evaluated to
unknown, never resolving to a real trap.
**Fix:** added an `initial` loop writing 0 to every word — included in the
`picorv32_ram.v` code above.

## 2.3 — First top-level wiring (CPU + RAM only, later superseded)

Set `PROGADDR_RESET = 0x00000000` and `STACKADDR = 0x00001FFC` (had to
override PicoRV32's default `0xFFFFFFFF`, which pointed outside the 8KB
RAM). This version is superseded by the final `picorv32_top.v` in section
2.8 below — not reproduced separately since only the final version matters.

## 2.4 — First testbench: illegal-instruction smoke test

#### `picorv32_top_tb.v`
```verilog
`timescale 1ns / 1ps

module picorv32_top_tb;

    reg clk = 0;
    reg resetn = 0;
    wire trap;

    always #5 clk = ~clk;

    picorv32_top dut (
        .clk    (clk),
        .resetn (resetn),
        .trap   (trap)
    );

    initial begin
        repeat (10) @(posedge clk);
        resetn = 1;
        $display("[%0t] resetn released, CPU should start fetching from 0x00000000", $time);
    end

    always @(posedge clk) begin
        if (resetn)
            $display("[%0t] pc=%h state=%b instr_trap=%b is_lui_auipc_jal=%b is_alu_reg_imm=%b mem_rdata_q=%h trap=%b",
                $time, dut.cpu.reg_pc, dut.cpu.cpu_state, dut.cpu.instr_trap,
                dut.cpu.is_lui_auipc_jal, dut.cpu.is_alu_reg_imm, dut.cpu.mem_rdata_q, trap);
    end

    always @(posedge clk) begin
        if (resetn && trap) begin
            $display("[%0t] trap asserted -- illegal instruction correctly detected at reset vector", $time);
            $display("STAGE A SMOKE TEST: PASS");
            $finish;
        end
    end

    initial begin
        #2000;
        $display("[%0t] TIMEOUT -- trap never asserted, check mem_valid/mem_ready handshake", $time);
        $display("STAGE A SMOKE TEST: FAIL");
        $finish;
    end

endmodule

```

**Result:** `PASS` — trap correctly asserted after the zero-init fix,
confirming reset, clocking, and the CPU-RAM handshake all work.

## 2.5 — First real firmware

#### `test.S`
```asm
.section .text
.global _start

_start:
    li      x1, 0xCAFEBABE
    li      x2, 0x00000100
    sw      x1, 0(x2)

loop:
    j       loop

```

#### `test.ld`
```text
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 8K
}

SECTIONS
{
    . = 0x00000000;
    .text : { *(.text*) } > RAM
    .data : { *(.data*) } > RAM
}

```

#### `bin2hex.py`
Converts a raw binary into one 32-bit hex word per line for `$readmemh`, matching the RAM's word-indexed array.

```python
#!/usr/bin/env python3
"""
bin2hex.py -- pack a little-endian RV32 binary into one 32-bit hex
word per line, matching picorv32_ram's word-indexed mem[] array for
$readmemh. Pads the final word with zero bytes if the binary isn't
a multiple of 4 bytes.

Usage: python3 bin2hex.py test.bin test.hex
"""
import sys

def main():
    if len(sys.argv) != 3:
        print("usage: bin2hex.py <input.bin> <output.hex>")
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    # Pad to a multiple of 4 bytes
    pad = (-len(data)) % 4
    data += b"\x00" * pad

    with open(sys.argv[2], "w") as out:
        for i in range(0, len(data), 4):
            word = data[i:i+4]
            # little-endian: last byte read is most significant
            value = int.from_bytes(word, byteorder="little")
            out.write(f"{value:08x}\n")

    print(f"Wrote {len(data)//4} words to {sys.argv[2]}")

if __name__ == "__main__":
    main()

```

#### `picorv32_program_tb.v`
```verilog
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

```

**Result:** `PASS` — `mem[0x100] = 0xcafebabe`, confirming the CPU
executes real instructions correctly, not just detects garbage.

## 2.6 — UART peripheral

#### `picorv32_uart_tx.v`
```verilog
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

```

#### `picorv32_addr_decoder.v (final version, all 4 peripherals)`
This is the FINAL version (RAM+UART+GPIO+Timer). It went through 3 revisions total as each peripheral was added; only the final is shown.

```verilog
// picorv32_addr_decoder.v
// Combinational address decoder: demuxes mem_valid to the addressed
// peripheral, muxes mem_ready/mem_rdata back to the CPU.
//
// Address map:
//   0x0000_0000 - 0x0000_1FFF : RAM
//   0x1000_0000 - 0x1000_00FF : UART
//   0x2000_0000 - 0x2000_00FF : GPIO
//   0x3000_0000 - 0x3000_00FF : Timer
//
// mem_addr/mem_wdata/mem_wstrb are NOT routed through this module --
// they fan out directly from the CPU to every peripheral in the top
// module. Only mem_valid (demux) and mem_ready/mem_rdata (mux) pass
// through here, since address decode is the only thing that differs
// per peripheral.
//
// Known simplification: an access to an unmapped address never
// completes (mem_ready stays low forever, CPU stalls). Fine for a
// controlled bring-up; a production SoC would want a decode-error
// timeout here.

module picorv32_addr_decoder (
    input  wire        mem_valid,
    input  wire [31:0] mem_addr,
    output wire         mem_ready,
    output wire [31:0]  mem_rdata,

    output wire        ram_valid,
    input  wire        ram_ready,
    input  wire [31:0] ram_rdata,

    output wire        uart_valid,
    input  wire        uart_ready,
    input  wire [31:0] uart_rdata,

    output wire        gpio_valid,
    input  wire        gpio_ready,
    input  wire [31:0] gpio_rdata,

    output wire        timer_valid,
    input  wire        timer_ready,
    input  wire [31:0] timer_rdata
);

    wire sel_ram   = (mem_addr[31:28] == 4'h0);
    wire sel_uart  = (mem_addr[31:28] == 4'h1);
    wire sel_gpio  = (mem_addr[31:28] == 4'h2);
    wire sel_timer = (mem_addr[31:28] == 4'h3);

    assign ram_valid   = mem_valid && sel_ram;
    assign uart_valid  = mem_valid && sel_uart;
    assign gpio_valid  = mem_valid && sel_gpio;
    assign timer_valid = mem_valid && sel_timer;

    assign mem_ready = sel_ram   ? ram_ready   :
                        sel_uart  ? uart_ready  :
                        sel_gpio  ? gpio_ready  :
                        sel_timer ? timer_ready :
                        1'b0;

    assign mem_rdata = sel_ram   ? ram_rdata   :
                        sel_uart  ? uart_rdata  :
                        sel_gpio  ? gpio_rdata  :
                        sel_timer ? timer_rdata :
                        32'hxxxxxxxx;

endmodule

```

#### `uart_test.S`
```asm
.section .text
.global _start

_start:
    li      x3, 0x10000000      /* UART base address */

wait_ready:
    lw      x4, 4(x3)            /* read TX_STATUS */
    andi    x4, x4, 1
    beqz    x4, wait_ready       /* loop until tx_ready bit is set */

    li      x5, 0x41             /* 'A' */
    sw      x5, 0(x3)            /* write TX_DATA -- starts transmission */

loop:
    j       loop

```

#### `picorv32_uart_tb.v`
```verilog
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

```

**Result:** `PASS` — testbench decoded the serial line bit-by-bit,
`Decoded byte: 0x41` (correct 'A'), with valid start/stop framing.

## 2.7 — C language support

#### `crt0.s`
```asm
/* crt0.s
 * Minimal C runtime startup.
 *
 * The stack pointer does NOT need to be set here -- PicoRV32 auto-loads
 * it from the STACKADDR parameter at reset (confirmed in picorv32.v).
 *
 * What this DOES need to do: zero out .bss (uninitialized C globals),
 * since C guarantees they start at zero but nothing does that
 * automatically. Then call main().
 */

.section .text
.global _start
.extern main

_start:
    la      t0, __bss_start
    la      t1, __bss_end

clear_bss:
    bge     t0, t1, bss_done
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       clear_bss

bss_done:
    call    main

hang:
    j       hang        /* if main() ever returns, stay here */

```

#### `c_test.ld`
```text
/* c_test.ld
 * Linker script for C programs, extending test.ld with proper .rodata
 * and .bss sections. __bss_start / __bss_end are the symbols crt0.s
 * uses to know which memory range to zero before main() runs.
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 8K
}

SECTIONS
{
    . = 0x00000000;

    .text : { *(.text*) } > RAM

    .rodata : { *(.rodata*) } > RAM   /* string literals, const data */

    .data : { *(.data*) } > RAM       /* initialized globals */

    .bss : {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > RAM
}

```

#### `main.c (first C program)`
```c
/* main.c
 * First C program: proves the full compile -> link -> run pipeline
 * works, using UART to send a short, visibly checkable string.
 */

#define UART_BASE       0x10000000
#define UART_TX_DATA    (*(volatile unsigned int *)(UART_BASE + 0x0))
#define UART_TX_STATUS  (*(volatile unsigned int *)(UART_BASE + 0x4))

static void uart_putc(char c)
{
    while (!(UART_TX_STATUS & 1)) {
        /* wait until tx_ready */
    }
    UART_TX_DATA = (unsigned int)c;
}

static void uart_puts(const char *s)
{
    while (*s) {
        uart_putc(*s);
        s++;
    }
}

int main(void)
{
    uart_puts("Hi");

    for (;;) {
        /* halt here forever */
    }

    return 0;
}

```

#### `picorv32_c_test_tb.v`
```verilog
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

```

**Result:** `PASS` — received `H` then `i` over UART, confirming the
full compile→link→run C pipeline works, including `.bss` zeroing and
function calls.

## 2.8 — GPIO peripheral

#### `picorv32_gpio.v`
```verilog
// picorv32_gpio.v
// Minimal 8-bit GPIO OUTPUT peripheral, native mem interface.
// Deliberately output-only for a fast first pass -- input/direction
// control is a reasonable later addition, not needed yet.
//
// Register map (offset from GPIO base, see picorv32_addr_decoder.v):
//   0x0  GPIO_DATA (read/write): bits [7:0] drive gpio_out directly.
//        Reading it back returns the last value written.

module picorv32_gpio (
    input  wire        clk,
    input  wire        resetn,

    input  wire        mem_valid,
    output reg          mem_ready,
    input  wire [31:0]  mem_addr,
    input  wire [31:0]  mem_wdata,
    input  wire [3:0]   mem_wstrb,
    output reg  [31:0]  mem_rdata,

    output reg  [7:0]   gpio_out
);

    always @(posedge clk) begin
        if (!resetn) begin
            mem_ready <= 1'b0;
            gpio_out  <= 8'b0;
        end else begin
            mem_ready <= 1'b0;

            if (mem_valid && !mem_ready) begin
                mem_ready <= 1'b1;

                if (mem_wstrb != 4'b0000) begin
                    gpio_out <= mem_wdata[7:0];
                end else begin
                    mem_rdata <= {24'b0, gpio_out};
                end
            end
        end
    end

endmodule

```

#### `main_gpio.c`
```c
/* main_gpio.c
 * Writes a test pattern to GPIO and holds it there.
 */

#define GPIO_BASE 0x20000000
#define GPIO_DATA (*(volatile unsigned int *)(GPIO_BASE + 0x0))

int main(void)
{
    GPIO_DATA = 0xAA;   /* 10101010 -- easy to visually verify */

    for (;;) {
        /* hold forever */
    }

    return 0;
}

```

#### `picorv32_gpio_tb.v`
```verilog
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

```

**Result:** `PASS` — `gpio_out = 0xaa`, exact match. All 4 prior
testbenches regression-tested and still passed after adding GPIO.

## 2.9 — Timer peripheral

#### `picorv32_timer.v`
```verilog
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

```

#### `main_timer.c`
```c
/* main_timer.c
 * Reads the free-running timer, burns some cycles in a loop, reads it
 * again, and stores both values to RAM so the testbench can check
 * that the counter genuinely advanced (not just left at a constant).
 */

#define TIMER_BASE  0x30000000
#define TIMER_COUNT (*(volatile unsigned int *)(TIMER_BASE + 0x0))

#define RESULT0 (*(volatile unsigned int *)(0x00000100))
#define RESULT1 (*(volatile unsigned int *)(0x00000104))

int main(void)
{
    unsigned int t0, t1;
    volatile int i;

    t0 = TIMER_COUNT;

    for (i = 0; i < 50; i++) {
        /* busy-loop delay */
    }

    t1 = TIMER_COUNT;

    RESULT0 = t0;
    RESULT1 = t1;

    for (;;) {
        /* halt here forever */
    }

    return 0;
}

```

#### `picorv32_timer_tb.v`
```verilog
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

```

## ERROR 6 — Timer test showed `t0=0 t1=0`
**Cause:** simulation window (`#2000`) was too short — a 50-iteration C
delay loop takes several clock cycles per iteration (compare, branch,
increment), so the program hadn't reached the store instructions yet when
the testbench checked.
**Fix:** increased the window to `#50000`. Result after fix: `t0=54,
t1=1898` — counter genuinely advanced (~37 cycles/loop iteration, a useful
real number).

**Result:** `PASS`. **Stage A is complete at this point**: CPU, RAM,
decoder, UART, GPIO, Timer — every piece independently simulation-verified,
all driven by real compiled C, with every addition regression-tested
against everything built before it.

## 2.10 — Final top-level wiring (all 4 peripherals)

#### `picorv32_top.v (final version)`
Went through 4 revisions as RAM-only → +decoder/UART → +GPIO → +Timer. Only the final version is shown.

```verilog
module picorv32_top (
    input  wire clk,
    input  wire resetn,
    output wire trap,
    output wire tx,          // UART serial output
    output wire [7:0] gpio_out,
    output wire [31:0] timer_out   // exposes current count for the testbench
);

    // CPU <-> decoder
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;

    // decoder <-> RAM
    wire        ram_valid;
    wire        ram_ready;
    wire [31:0] ram_rdata;

    // decoder <-> UART
    wire        uart_valid;
    wire        uart_ready;
    wire [31:0] uart_rdata;

    // decoder <-> GPIO
    wire        gpio_valid;
    wire        gpio_ready;
    wire [31:0] gpio_rdata;

    // decoder <-> Timer
    wire        timer_valid;
    wire        timer_ready;
    wire [31:0] timer_rdata;

    picorv32 #(
        .PROGADDR_RESET (32'h0000_0000),
        .STACKADDR      (32'h0000_1FFC),
        .ENABLE_IRQ     (0),
        .ENABLE_PCPI    (0)
    ) cpu (
        .clk       (clk),
        .resetn    (resetn),
        .trap      (trap),

        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),

        .mem_la_read  (),
        .mem_la_write (),
        .mem_la_addr  (),
        .mem_la_wdata (),
        .mem_la_wstrb (),

        .pcpi_valid (),
        .pcpi_insn  (),
        .pcpi_rs1   (),
        .pcpi_rs2   (),
        .pcpi_wr    (1'b0),
        .pcpi_rd    (32'b0),
        .pcpi_wait  (1'b0),
        .pcpi_ready (1'b0),

        .irq (32'b0),
        .eoi (),

        .trace_valid (),
        .trace_data  ()
    );

    picorv32_addr_decoder decoder (
        .mem_valid (mem_valid),
        .mem_addr  (mem_addr),
        .mem_ready (mem_ready),
        .mem_rdata (mem_rdata),

        .ram_valid (ram_valid),
        .ram_ready (ram_ready),
        .ram_rdata (ram_rdata),

        .uart_valid (uart_valid),
        .uart_ready (uart_ready),
        .uart_rdata (uart_rdata),

        .gpio_valid (gpio_valid),
        .gpio_ready (gpio_ready),
        .gpio_rdata (gpio_rdata),

        .timer_valid (timer_valid),
        .timer_ready (timer_ready),
        .timer_rdata (timer_rdata)
    );

    picorv32_ram #(
        .WORDS (2048)
    ) ram (
        .clk       (clk),
        .mem_valid (ram_valid),
        .mem_ready (ram_ready),
        .mem_wstrb (mem_wstrb),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (ram_rdata)
    );

    picorv32_uart_tx #(
        .CLKS_PER_BIT (4)
    ) uart (
        .clk       (clk),
        .resetn    (resetn),
        .mem_valid (uart_valid),
        .mem_ready (uart_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (uart_rdata),
        .tx        (tx)
    );

    picorv32_gpio gpio (
        .clk       (clk),
        .resetn    (resetn),
        .mem_valid (gpio_valid),
        .mem_ready (gpio_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (gpio_rdata),
        .gpio_out  (gpio_out)
    );

    picorv32_timer timer (
        .clk       (clk),
        .resetn    (resetn),
        .mem_valid (timer_valid),
        .mem_ready (timer_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (timer_rdata),
        .count     (timer_out)
    );

endmodule

```

---

# PART 3 — Stage B: Zephyr SoC/Board Port (in progress)

## Architectural decisions made before writing files

1. **WSL2 over VirtualBox** for the whole project (see Part 1).
2. **Simple `SOC_ROOT`/`BOARD_ROOT`/`DTS_ROOT` approach over a full Zephyr
   "module"** (`module.yml`/`ZEPHYR_EXTRA_MODULES`) — found documented
   rough edges (a real Zephyr GitHub issue with unresolved Kconfig
   dependencies for an out-of-tree RISC-V SoC family) for the module route;
   the simpler root-variable approach is Zephyr's own documented method for
   "board/platform not yet supported."
3. **SoC name:** `picorv32_soc`. **Board name:** `picorv32_board`, vendor
   `others` (Zephyr's documented fallback for non-commercial boards).

## 3.1 — SoC layer files

#### `soc.yml`
```yaml
# soc.yml
# Minimal SoC YAML per Zephyr's hardware model v2 -- describes just one
# SoC, no family/series grouping needed since this isn't part of a
# broader chip family.
socs:
  - name: picorv32_soc

```

#### `Kconfig.soc (corrected version)`
Originally included `select RISCV` directly here — corrected after finding the real Zephyr convention puts that in the plain `Kconfig` file instead, keeping `Kconfig.soc` limited to identity + ISA-extension selects.

```text
# Kconfig.soc
# Identity symbol + ISA extension selects only. The architecture
# select (RISCV) itself belongs in the plain Kconfig file below, per
# Zephyr convention -- Kconfig.soc should only describe what this SoC
# IS, not pull in the base architecture.

config SOC_PICORV32_SOC
	bool
	select RISCV_ISA_RV32I

config SOC
	default "picorv32_soc" if SOC_PICORV32_SOC

```

#### `Kconfig (plain, new file added during the correction)`
```text
# Kconfig
# SoC-specific settings, including the architecture select. This file
# is sourced by soc/Kconfig automatically.

config SOC_PICORV32_SOC
	select RISCV

```

#### `soc.h`
```c
/* soc.h
 * SoC-specific configuration macros. Empty for now -- populated as
 * the port grows (e.g. timer/interrupt register definitions later).
 */
#ifndef PICORV32_SOC_SOC_H_
#define PICORV32_SOC_SOC_H_

#endif /* PICORV32_SOC_SOC_H_ */

```

#### `CMakeLists.txt (SoC level)`
```cmake
# CMakeLists.txt
# Uses Zephyr's default RISC-V linker script to start. A custom
# linker.ld is only needed if this default doesn't fit our memory map
# -- something we'll find out from the first real build attempt rather
# than assuming up front.

zephyr_include_directories(.)

set(SOC_LINKER_SCRIPT ${ZEPHYR_BASE}/include/zephyr/arch/riscv/common/linker.ld CACHE INTERNAL "")

```

## 3.2 — Board layer files

#### `board.yml (fixed version)`
First version was missing `full_name` — see Error 8 below.

```yaml
# board.yml
# Links this board to the picorv32_soc SoC defined under
# zephyr-app/soc/riscv/picorv32_soc/.

board:
  name: picorv32_board
  full_name: PicoRV32 Custom SoC Board
  vendor: others
  socs:
    - name: picorv32_soc

```

#### `Kconfig.picorv32_board`
```text
# Kconfig.picorv32_board
# Board-level Kconfig symbol. No bool type/prompt needed -- the build
# system auto-generates BOARD_PICORV32_BOARD's type from board.yml.
# Just select the SoC this board uses.

config BOARD_PICORV32_BOARD
	select SOC_PICORV32_SOC

```

#### `picorv32_board_defconfig`
```text
# picorv32_board_defconfig
# Intentionally minimal for now. No CONFIG_SERIAL/CONFIG_CONSOLE lines
# yet -- there's no Zephyr UART *driver* written for this board yet
# (only the peripheral RTL exists), so enabling console options here
# would just fail to find a matching driver. Settings get added here
# once the driver exists.

```

#### `board.cmake`
```text
# board.cmake
# Normally defines flash/debug runner arguments (e.g. openocd, jlink).
# Left empty for now -- this board isn't flashed to real hardware yet,
# only built and simulated. Will be filled in once real hardware
# flashing is set up.

```

## 3.3 — Devicetree

Reference used: the real, working `qemu_riscv32` board's `.dts` and
included `.dtsi` files, pulled directly from the user's own Zephyr
checkout (guaranteed version-compatible), rather than a generic web
example. Adapted heavily: single core (not 8), no CLINT/PLIC (interrupts
not wired up yet), no PCIe/virtio, RV32I-only ISA claim (matching every
`-march=rv32i` compile done throughout Stage A).

#### `picorv32_board.dts`
```dts
/*
 * Devicetree for picorv32_board, adapted from Zephyr's own
 * qemu_riscv32 reference (dts/riscv/qemu/virt-riscv.dtsi +
 * virt-riscv32.dtsi), trimmed down to match this actual hardware:
 * single core, no CLINT/PLIC (interrupts not wired up yet), no
 * PCIe/virtio, and only the RV32I base ISA (matches every -march=rv32i
 * compile done so far -- no m/a/f/d/c/zicsr/zifencei claimed, since
 * the hardware hasn't been proven to support them).
 */

/dts-v1/;

/ {
	#address-cells = <0x01>;
	#size-cells = <0x01>;
	compatible = "picorv32,picorv32-soc";
	model = "PicoRV32 Custom SoC";

	chosen {
		zephyr,sram = &ram0;
		zephyr,console = &uart0;
		zephyr,shell-uart = &uart0;
	};

	cpus {
		#address-cells = <0x01>;
		#size-cells = <0x00>;

		cpu@0 {
			device_type = "cpu";
			reg = <0x00>;
			status = "okay";
			compatible = "picorv32,picorv32", "riscv";

			riscv,isa-base = "rv32i";
			riscv,isa-extensions = "i";

			hlic0: interrupt-controller {
				compatible = "riscv,cpu-intc";
				#address-cells = <0>;
				#interrupt-cells = <0x01>;
				interrupt-controller;
			};
		};
	};

	/* Matches picorv32_ram.v: 2048 words x 4 bytes = 0x2000 (8KB) */
	ram0: memory@0 {
		device_type = "memory";
		reg = <0x00000000 0x00002000>;
	};

	soc {
		#address-cells = <0x01>;
		#size-cells = <0x01>;
		compatible = "simple-bus";
		ranges;

		/* Matches picorv32_addr_decoder.v: UART at 0x10000000 */
		uart0: uart@10000000 {
			compatible = "picorv32,uart";
			reg = <0x10000000 0x100>;
			status = "okay";
		};
	};
};

```

## 3.4 — Devicetree binding

Reference used: `aesc,uart.yaml` (a real, small, minimal binding already
in the Zephyr tree) plus `uart-controller.yaml` (confirmed nothing in it is
`required: true`, so our fixed-baud-rate UART doesn't need `current-speed`).

#### `picorv32,uart.yaml`
```yaml
# picorv32,uart.yaml
description: |
  Custom UART transmitter for the PicoRV32 SoC (see picorv32_uart_tx.v).
  Transmit-only, fixed baud rate set at synthesis time via the
  CLKS_PER_BIT Verilog parameter -- not software-configurable, so no
  current-speed property is used here.

compatible: "picorv32,uart"

include: [uart-controller.yaml]

properties:
  reg:
    required: true

```

## 3.5 — Application files (first buildable target)

#### `CMakeLists.txt (application root)`
```cmake
# CMakeLists.txt (application root)
# Registers our custom SoC/board/devicetree-binding directories with
# Zephyr's build system BEFORE find_package(Zephyr) runs, since that's
# when Zephyr scans these root variables.

cmake_minimum_required(VERSION 3.20.0)

list(APPEND BOARD_ROOT ${CMAKE_CURRENT_SOURCE_DIR})
list(APPEND SOC_ROOT ${CMAKE_CURRENT_SOURCE_DIR})
list(APPEND DTS_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(picorv32_zephyr_app)

target_sources(app PRIVATE src/main.c)

```

#### `prj.conf (fixed version)`
First version was empty — see Error 10 below for why `CONFIG_SYS_CLOCK_EXISTS=n` was added.

```text
# prj.conf
#
# CONFIG_SYS_CLOCK_EXISTS=n: this system genuinely has no interrupt-
# driving timer yet (picorv32_timer.v exists in hardware, but no
# Zephyr driver has been written for it -- that's deliberately a
# later step). This tells Zephyr's kernel honestly not to expect one,
# rather than us faking timer Kconfig values that don't reflect real
# hardware capability. Once a real timer driver exists, this line
# comes back out.
CONFIG_SYS_CLOCK_EXISTS=n

```

#### `src/main.c`
Deliberately minimal (no printk/console) to isolate whether the SoC/board/devicetree/Kconfig chain resolves at all, before adding driver complexity.

```c
/* main.c
 * Deliberately minimal for the first Zephyr build attempt on this
 * SoC -- no printk/console calls, since no UART driver exists yet
 * (only the devicetree binding). This isolates one thing at a time:
 * does the SoC/board/devicetree/Kconfig chain even resolve and link,
 * before adding driver complexity on top.
 */

int main(void)
{
	while (1) {
		/* nothing yet */
	}

	return 0;
}

```

## ERROR 7 — `west: unknown command "build"`
**Cause:** `west build` was run from inside `zephyr-app/`, which is
outside the actual west workspace (`~/zephyrproject`, where the `.west`
config folder lives). West needs to be invoked from somewhere it can find
that folder.
**Fix:** ran from `~/zephyrproject`, pointed at the app via its full path
as an argument, with `-d` specifying where to put build output:
```bash
cd ~/zephyrproject
west build -b picorv32_board /mnt/e/picorv32-zephyr-soc/zephyr-app \
    -d /mnt/e/picorv32-zephyr-soc/zephyr-app/build
```

## ERROR 8 — `board.yml ... is not valid under any of the given schemas`
**Cause:** Zephyr's board schema (`scripts/schemas/board-schema.yaml`,
checked directly rather than guessed) requires `name` AND `full_name`
together — the first `board.yml` only had `name` and `vendor`.
**Fix:** added `full_name: PicoRV32 Custom SoC Board`.

## ERROR 9 — `operator '==' has no left operand` on `CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC`
**Cause:** got past devicetree generation and Kconfig parsing — first real
compile attempt. Zephyr's kernel expects a system timer *driver* to define
this value from real hardware clock frequency; no such driver exists yet
(deliberately deferred — the Timer peripheral exists in RTL, but no Zephyr
driver was written for it).
**Fix:** added `CONFIG_SYS_CLOCK_EXISTS=n` to `prj.conf` — tells the kernel
honestly that no timer exists yet, rather than faking values that don't
reflect real hardware capability.

## ERROR 10 (CURRENT, UNRESOLVED) — `CONFIG_NUM_IRQS undeclared` + `extension 'zicsr' required`
**First part (`CONFIG_NUM_IRQS`):** minor — our SoC's Kconfig never
declared how many interrupt lines exist, even as a placeholder minimum.
Straightforward fix, not yet applied (superseded by the bigger issue
below).

**Second part — the real finding:** the assembler rejected
`csrrc a5, mstatus, 8` / `csrs mstatus, a5`, instructions Zephyr's RISC-V
architecture layer uses UNCONDITIONALLY for interrupt lock/unlock (basic
critical-section support, needed even without real interrupt peripherals
wired up). This isn't a Kconfig omission — it's the ISA declaration
(`Kconfig.soc`'s `RISCV_ISA_RV32I`-only claim) being accurate: the
toolchain won't emit those instructions without the `zicsr` extension.

**Deeper investigation (verified directly against `picorv32.v` source):**
PicoRV32 only decodes 4 specific hardcoded CSR addresses (`rdcycle`,
`rdcycleh`, `rdinstr`, `rdinstrh` — read-only performance counters). There
is no general CSR read/write logic. A `csrrc ..., mstatus, ...` instruction
would not just be unhandled — on real execution it would very likely
**trap as illegal**, via the same illegal-instruction mechanism exploited
deliberately in Stage A's very first smoke test (Section 2.4).

Further, PicoRV32's actual interrupt-masking mechanism is a completely
non-standard custom instruction (`maskirq`, custom opcode `0001011`), NOT
the standard RISC-V `mstatus`/`mie`/`mip` CSR model Zephyr's generic
RISC-V arch layer assumes, with no override hook available.

**Status: unresolved, decision pending.** Three options were presented:
1. Extend `picorv32.v` with real Zicsr/`mstatus` CSR support (recommended
   — most differentiated outcome, directly extends the RTL work already
   done, but is real bounded RTL work: new decode logic, new register,
   dedicated testbench)
2. Swap CPU cores for the Zephyr port specifically, keeping vanilla
   PicoRV32 for the already-complete Stage A portfolio piece
3. Look for an existing community fork of PicoRV32 with Zicsr already added

No decision made yet as of this report.

---

# Current overall status

- **Stage A: complete and fully verified.** CPU, RAM, address decoder,
  UART, GPIO, Timer — all independently simulation-tested, all driven by
  real compiled C, every addition regression-tested.
- **Stage B: in progress, blocked on a real hardware capability gap.**
  SoC layer, board layer, devicetree, and one devicetree binding are
  written and have gotten a real `west build` attempt through devicetree
  generation and Kconfig parsing, into actual compilation — where it hit
  PicoRV32's lack of standard CSR support, a genuine architectural
  limitation rather than a configuration mistake.
- **Next decision needed:** which of the 3 options above to pursue for
  resolving the CSR gap before Stage B can continue.
