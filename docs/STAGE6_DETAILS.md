# Stage 6 — Zephyr RTOS port (in progress)

Everything through Stage 5 was “bare-metal” — hand-written code talking directly to the hardware. Stage 6’s goal is different: get Zephyr, a professional embedded operating system, to run on the custom CPU instead. Zephyr handles things like task scheduling, memory management, and driver frameworks — but it doesn’t know the custom hardware exists. Stage 6 is entirely about teaching it.

## Decision 1 — how to plug custom hardware into Zephyr

Zephyr supports two ways to add hardware it doesn’t know about: a full “module” (a formal plugin system), or simply pointing Zephyr at extra folders (`SOC_ROOT`, `BOARD_ROOT`, `DTS_ROOT`) containing custom files. 

**Decision:** Chose the simpler folder-pointing approach based on Zephyr's documented method for "hardware not yet supported," avoiding unresolved errors associated with the module approach for out-of-tree RISC-V chips.

## The SoC layer — “this chip exists”

**Location:** `zephyr-app/soc/riscv/picorv32_soc/`
This set of files answers one question for Zephyr: what is this chip capable of?

*   **`soc.yml`** — the identity card. Just says “there’s an SoC called picorv32_soc.” Validated by Zephyr’s Python/CMake build scripts.
*   **`Kconfig.soc`** — declares the chip’s ISA (instruction set). Deliberately declared only plain `RV32I` matching exact compilation usage.
*   **`Kconfig`** — declares that this chip uses the RISC-V architecture (`select RISCV`). 
*   **`soc.h`** — a C header for chip-specific settings. Currently an empty placeholder.
*   **`CMakeLists.txt`** — tells the build system which linker script to use. Pointed at Zephyr’s generic RISC-V linker script.

## The board layer — “here’s a specific board using that chip”

**Location:** `zephyr-app/boards/others/picorv32_board/`
A “board” is a specific arrangement of a chip plus surrounding circuitry (simulated).

*   **`board.yml`** — links the board name to the SoC name. (Fixed schema error by adding `full_name`).
*   **`Kconfig.picorv32_board`** — says “this board uses picorv32_soc.”
*   **`picorv32_board_defconfig`** — default settings. Left almost empty since enabling a serial console requires a driver that doesn’t exist yet.
*   **`board.cmake`** — normally configures flashing/debugging. Left empty for simulation.

## The devicetree — “here’s exactly where everything lives”

**File:** `picorv32_board.dts`
A structured description of hardware. Tells Zephyr where the CPU is, RAM locations, and UART addresses.

Adapted from working devicetree files for `qemu_riscv32` to guarantee compatibility. Trimmed from 8 cores down to 1, removed virtual interrupt controller/timer, and added the custom UART address (`0x10000000`).

## The devicetree binding — “teaching Zephyr what your UART’s properties mean”

**File:** `picorv32,uart.yaml`
A schema describing allowed properties for the device. Based on a small existing binding (`aesc,uart.yaml`), confirming no fields were mandatory (avoiding faking a configurable baud rate for the fixed-baud-rate UART).

## The application — the actual buildable thing

*   **`CMakeLists.txt` (app root)** — points Zephyr’s build system to the custom folders.
*   **`prj.conf`** — project-specific settings.
*   **`src/main.c`** — deliberately bare to isolate compile chain complexity.

## The actual build attempts and discoveries

`west build` execution taught specific lessons:

1.  **`west: unknown command "build"`**: Ran from wrong folder. Fixed by running from `~/zephyrproject` pointing at the app path.
2.  **`board.yml` schema error**: Fixed by adding `full_name`.
3.  **`CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC == 0`**: Zephyr expects a system timer driver. Fixed by adding `CONFIG_SYS_CLOCK_EXISTS=n`.
4.  **`CONFIG_NUM_IRQS` undeclared + `zicsr` required (Blocker)**: Zephyr unconditionally uses special RISC-V instructions (`csrrc`, `csrs`) to lock/unlock interrupts. PicoRV32 uses a completely different, non-standard way of handling interrupts. This is a real hardware capability gap, not a settings problem.

## Current Status

Everything up through the devicetree and application layer is built and works up to compilation. The project is paused at this genuine hardware gap, leaving a solid foundation and a clearly documented architectural decision for the future.
