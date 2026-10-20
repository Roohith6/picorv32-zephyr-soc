# picorv32-zephyr-soc: Detailed Project Report

Everything done in this project so far, in order, with results, errors and
how each was resolved. Complete source listings of every file are in
`FULL_LOG.md` (the code appendix). This document is the
narrative and the status.

---

## 1. What this project is

A small RISC-V computer built from scratch in Verilog around the
PicoRV32 CPU core, with a custom set of memory-mapped peripherals, tested
entirely in simulation. The second goal was to port the Zephyr RTOS to
it. The first goal is complete; the second is paused at a hardware gap.

| Item | Value |
|---|---|
| CPU | PicoRV32 (RV32I, third-party, unmodified, from YosysHQ) |
| Memory | 8 KB RAM, 2048 x 32-bit words |
| Peripherals | UART TX, 8-bit GPIO output, 32-bit free-running Timer |
| Bus | PicoRV32's native memory interface (**not AXI**) |
| Simulator | Icarus Verilog |
| Firmware toolchain | `riscv64-zephyr-elf-gcc` from Zephyr SDK 1.0.1 |
| RTOS target | Zephyr 4.4.99, west 1.5.0, CMake 4.2.3, Python 3.14.4 |
| Environment | WSL2 Ubuntu on Windows, Python venv `~/zephyrproject-venv` |
| Project folder | `/mnt/e/picorv32-zephyr-soc/` |

## 2. Final architecture

```
PicoRV32 CPU
     |  native memory interface
     v
Address decoder (mem_addr[31:28])
  |-- 0x0 -> RAM    0x0000_0000 - 0x0000_1FFF
  |-- 0x1 -> UART   0x1000_0000 - 0x1000_00FF
  |-- 0x2 -> GPIO   0x2000_0000 - 0x2000_00FF
  `-- 0x3 -> Timer  0x3000_0000 - 0x3000_00FF
```

**Bus protocol (valid/ready):**

| Signal | Direction | Meaning |
|---|---|---|
| `mem_valid` | CPU out | CPU requests a transaction |
| `mem_ready` | CPU in | Peripheral completed it |
| `mem_addr`, `mem_wdata` | CPU out | 32-bit address and write data |
| `mem_wstrb` | CPU out | Byte enables; `0000` = read |
| `mem_rdata` | CPU in | Read data |
| `mem_instr` | CPU out | 1 = instruction fetch |

Every peripheral answers one cycle after `mem_valid`.

**Register maps:**

| Peripheral | Offset | Register | Behaviour |
|---|---|---|---|
| UART | `+0x0` | TX_DATA | Write a byte to start transmitting |
| UART | `+0x4` | TX_STATUS | Bit 0 = ready (idle) |
| GPIO | `+0x0` | GPIO_DATA | Bits [7:0] drive `gpio_out`; read returns last write |
| Timer | `+0x0` | TIMER_COUNT | Read = count (+1 every clock); write = reload |

CPU settings in `picorv32_top.v`: `PROGADDR_RESET = 0x0`,
`STACKADDR = 0x1FFC` (PicoRV32's default `0xFFFFFFFF` points outside
this RAM), `ENABLE_IRQ = 0`, `ENABLE_PCPI = 0`.

## 3. What was done, in order

### Phase 0: environment

1. Moved from a VirtualBox Ubuntu VM to WSL2 Ubuntu (faster, simpler
   tool installs; Cadence is used separately on college lab machines).
2. Installed Icarus Verilog, GTKWave, Yosys, build tools, and the Zephyr
   SDK 1.0.1 toolchain.
3. Put `west` in a Python venv, with a `zenv` alias to reactivate it.
4. Verified the whole toolchain by building and booting Zephyr's
   `hello_world` on `qemu_riscv32`. It printed
   `Hello World! qemu_riscv32/qemu_virt_riscv32`, and used 28,800 B of
   RAM. That figure matters later (see section 8).

### Phase 1: CPU + RAM

1. Downloaded `picorv32.v` (3049 lines, unmodified).
2. Wrote `picorv32_ram.v` and a first `picorv32_top.v` wiring CPU to RAM.
3. **Smoke test** (`picorv32_top_tb.v`): all-zero RAM is not a valid
   instruction, so a correctly wired CPU must raise `trap`. It did, at
   175 ns, once the RAM zero-init bug (Error 5) was fixed.
4. **First firmware**: `test.S` + `test.ld` store `0xCAFEBABE` at
   `0x100` and loop. Built the pipeline: assemble/link, `objcopy -O binary`,
   `bin2hex.py`, then `$readmemh` into `dut.ram.mem` from the testbench.
5. **Program test** (`picorv32_program_tb.v`): `mem[0x100] == 0xCAFEBABE`.
   Passed.

### Phase 2: UART

1. Wrote `picorv32_addr_decoder.v` (RAM + UART routes) and
   `picorv32_uart_tx.v`, a real 8N1 shift-register transmitter, not a
   simulation shortcut.
2. Rewired `picorv32_top.v` through the decoder. Re-ran both earlier
   tests as a regression; both still passed.
3. **UART test**: `uart_test.S` polls TX_STATUS then writes `'A'`.
   `picorv32_uart_tb.v` acts as a serial receiver: it waits for the
   start bit, samples each bit mid-period, checks the stop bit. Decoded
   `0x41`. Passed.

### Phase 3: C support

1. `crt0.s` zeroes `.bss` and calls `main`. It does not set the stack
   pointer: PicoRV32 loads `x2` from the `STACKADDR` parameter at reset
   (confirmed in the source).
2. `c_test.ld` adds `.rodata`, `.data`, `.bss` and the `__bss_start` /
   `__bss_end` symbols.
3. `main.c` has a small UART driver (`uart_putc`, `uart_puts`) and sends
   `"Hi"`. `picorv32_c_test_tb.v` decodes two bytes. Passed (`H`, `i`).

### Phase 4: GPIO

`picorv32_gpio.v`, decoder and top updated for a third peripheral, all
earlier tests re-run (4 regressions, all pass). `main_gpio.c` writes
`0xAA`; `picorv32_gpio_tb.v` checks the pins. Passed.

### Phase 5: Timer

`picorv32_timer.v`, decoder and top updated for a fourth peripheral
(5 regressions, all pass). `main_timer.c` reads the counter, runs a
50-iteration loop, reads again and stores both values; the testbench
checks `t1 > t0`. Measured `t0=54, t1=1898`, about 37 clock cycles per
iteration of a `-O0` C loop. Passed.

### Phase 6: Zephyr port (written, build paused)

1. **Approach.** Rejected the full Zephyr "module" route
   (`module.yml`, `ZEPHYR_EXTRA_MODULES`) after finding documented
   problems with out-of-tree RISC-V SoCs. Used `SOC_ROOT` / `BOARD_ROOT`
   / `DTS_ROOT` set in the app's `CMakeLists.txt` instead.
2. **SoC layer** (`soc/riscv/picorv32_soc/`): `soc.yml`, `Kconfig.soc`,
   `Kconfig`, `soc.h`, `CMakeLists.txt`. Declares plain RV32I only,
   matching every `-march=rv32i` compile so far.
3. **Board layer** (`boards/others/picorv32_board/`): `board.yml`,
   `Kconfig.picorv32_board`, `picorv32_board_defconfig`, `board.cmake`,
   `picorv32_board.dts`.
4. **Devicetree.** Adapted from the working `qemu_riscv32` files in your
   own Zephyr checkout (same version, so compatible), trimmed to one
   core, RAM, and the UART; no CLINT/PLIC.
5. **UART binding** `picorv32,uart.yaml`, modelled on a small existing
   binding; nothing in the base UART schema is mandatory.
6. **App**: `CMakeLists.txt`, `prj.conf`, `src/main.c` (an empty loop,
   deliberately, to test the build chain on its own).
7. **Build**: `west build -b picorv32_board ...` runs through devicetree
   generation and Kconfig, then stops during compilation (section 6).

## 4. Files

| Folder | Files |
|---|---|
| `rtl/` | `picorv32.v`, `picorv32_ram.v`, `picorv32_addr_decoder.v`, `picorv32_uart_tx.v`, `picorv32_gpio.v`, `picorv32_timer.v`, `picorv32_top.v` |
| `tb/` | `picorv32_top_tb.v`, `picorv32_program_tb.v`, `picorv32_uart_tb.v`, `picorv32_c_test_tb.v`, `picorv32_gpio_tb.v`, `picorv32_timer_tb.v` |
| `fw/` | `test.S`, `test.ld`, `uart_test.S`, `crt0.s`, `c_test.ld`, `bin2hex.py`, `main.c`, `main_gpio.c`, `main_timer.c` (plus generated `.o/.elf/.bin/.hex`) |
| `zephyr-app/` | `CMakeLists.txt`, `prj.conf`, `src/main.c`, `soc/...` (5 files), `boards/...` (5 files), `dts/bindings/serial/picorv32,uart.yaml` |

## 5. Test results

All six testbenches pass in Icarus Verilog, and were re-run after every
change to the decoder or top level.

| Testbench | Checks | Result |
|---|---|---|
| `picorv32_top_tb.v` | Illegal instruction at reset vector raises `trap` | Pass, 175 ns |
| `picorv32_program_tb.v` | RAM store: `mem[0x100] == 0xCAFEBABE` | Pass |
| `picorv32_uart_tb.v` | Serial line decodes to `0x41`, framing correct | Pass |
| `picorv32_c_test_tb.v` | C firmware sends `"Hi"` over UART | Pass |
| `picorv32_gpio_tb.v` | `gpio_out == 0xAA` | Pass |
| `picorv32_timer_tb.v` | Counter advanced (`t0=54`, `t1=1898`) | Pass |

## 6. The Zephyr blocker, stated precisely

**What was verified directly in `picorv32.v`:**
- The only CSR accesses it decodes are four read-only counters:
  `rdcycle`, `rdcycleh`, `rdinstr`, `rdinstrh`.
- Its interrupt masking is a custom `maskirq` instruction (custom opcode
  `0001011`), gated by `ENABLE_IRQ`. It is not the standard
  `mstatus`/`mie`/`mip` model.

**What the build showed:** the assembler rejected
`csrrc a5, mstatus, 8` and `csrs mstatus, a5` (`zicsr` required). Zephyr's
RISC-V code uses these for interrupt lock/unlock, even with no interrupt
peripherals present.

**Options:**

| Option | What it takes | Trade-off |
|---|---|---|
| Extend PicoRV32 | CSR file, trap entry, `mret`, interrupt path, new testbench | Strongest story, but a sizeable RTL project on its own |
| Switch to a supported core | Replace the CPU; Zephyr already supports NEORV32 | Fastest route to a booting Zephyr, but no longer PicoRV32 |
| Stop here | Document the finding, mark `zephyr-app/` work in progress | The hardware, firmware and tests are already a finished deliverable |

## 7. Errors and fixes, in order

| # | Error | Cause | Fix |
|---|---|---|---|
| 1 | `pip install --user west`: externally-managed-environment | Ubuntu's PEP 668 protection | Created a venv, installed west inside it |
| 2 | Zephyr SDK download 404 | Guessed an old filename format; v1.0.x ships `_minimal` / `_gnu` bundles | Used the real release filename |
| 3 | `No module named 'jsonschema'` | Requirements not fully installed in the venv. | Reinstalled requirements |
| 4 | `pkg-config libusb-1.0 not found` (building `hidapi`) | Full `requirements.txt` includes NXP flashing tools | Installed only `requirements-base.txt` and `requirements-build-test.txt` |
| 5 | First smoke test timed out; `mem_rdata_q` stuck at `x` | Verilog arrays start as `x`, not 0 | Added a zero-init loop to `picorv32_ram.v` |
| 6 | Timer test showed `t0=0 t1=0` | 2 us wait was too short for a 50-iteration loop | Raised wait to 50 us |
| 7 | `west: unknown command "build"` | Ran from outside the west workspace | Ran from `~/zephyrproject` with the app's full path and `-d` |
| 8 | `board.yml` not valid under the schema | Missing `full_name` | Added `full_name` |
| 9 | `CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC == 0` compile error | No system timer driver exists | `CONFIG_SYS_CLOCK_EXISTS=n` in `prj.conf` |
| 10 | `CONFIG_NUM_IRQS` undeclared; `zicsr` required | NUM_IRQS never defined. zicsr gap is the blocker in section 6 | **Open** |

## 8. Limitations of the current design

- **No AXI.** The project was first described as "AXI4-Lite SoC". That
  was never built; the design stays on PicoRV32's native interface.
- **Simulation only.** Nothing has been synthesized, placed, or run on
  an FPGA in this project.
- **No interrupts.** `ENABLE_IRQ = 0`; the Timer cannot raise anything.
- **UART:** transmit only; baud rate fixed at synthesis. `CLKS_PER_BIT = 4`
  is for fast simulation. A real board needs `clock_hz / baud`.
- **GPIO:** output only; no input path.
- **Unmapped addresses** never complete, so the CPU stalls forever.
- **RAM:** the zero-init loop is a simulation convenience; real RAM
  powers up undefined. At 8 KB it is almost certainly too small for
  Zephyr (the QEMU hello_world used 28,800 B).
- **Tests are directed**, one scenario each, not random or coverage
  driven.

## 9. What remains

**To finish the Zephyr port** (if you continue):
1. Decide the core question (section 6 options).
2. Define `CONFIG_NUM_IRQS`.
3. Make the Timer interrupt-driven and write a system timer driver.
4. Enlarge the RAM and update the devicetree `reg`.
5. Write a Zephyr UART driver, then enable the console in `prj.conf`.
6. Optionally add GPIO and Timer devicetree nodes and bindings.
7. Boot an image on the simulated SoC and check "Hello World" with a
   UART-decoding testbench.

## 10. How to reproduce

From the project root, run every testbench:

```bash
cd /mnt/e/picorv32-zephyr-soc
RTL="rtl/picorv32.v rtl/picorv32_ram.v rtl/picorv32_uart_tx.v rtl/picorv32_gpio.v rtl/picorv32_timer.v rtl/picorv32_addr_decoder.v rtl/picorv32_top.v"
for tb in picorv32_top_tb picorv32_program_tb picorv32_uart_tb picorv32_c_test_tb picorv32_gpio_tb picorv32_timer_tb; do
  echo "--- $tb ---"
  iverilog -g2012 -o sim.out $RTL tb/$tb.v && vvp sim.out | tail -3
done
```

Rebuild a firmware image:
```bash
cd fw
GCC=~/zephyr-sdk-1.0.1/riscv64-zephyr-elf/bin/riscv64-zephyr-elf
${GCC}-gcc -c crt0.s -o crt0.o -march=rv32i -mabi=ilp32
${GCC}-gcc -c main.c -o main.o -march=rv32i -mabi=ilp32 -O0 -ffreestanding -nostdlib
${GCC}-gcc -nostdlib -nostartfiles -T c_test.ld -o c_test.elf crt0.o main.o -march=rv32i -mabi=ilp32
${GCC}-objcopy -O binary c_test.elf c_test.bin
python3 bin2hex.py c_test.bin c_test.hex
```
