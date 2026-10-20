# Building a RISC-V SoC from scratch — full walkthrough

This is the story of everything built so far in the PicoRV32 + Zephyr SoC
project, explained step by step. Each section covers: what we were trying to
do, what tool we used, what the code actually does (in plain language), and
how we knew it worked.

**The big picture, in one analogy:** think of a computer chip as a tiny
factory. The **CPU** is a worker who reads instructions one at a time and
does exactly what they say. **RAM** is a notebook sitting next to the worker
— it holds both the instructions and any scratch notes. A **peripheral**
(like UART) is a piece of equipment the worker can operate, like a telephone
for sending messages outside the factory. The **address decoder** is a
receptionist who looks at which "extension number" the worker is dialing
and connects the call to the right piece of equipment — the notebook, or
the telephone.

Everything below is building exactly that factory, one verified piece at a
time.

---

## Step 1 — Setting up the toolbox (WSL2 + toolchain install)

**Goal:** get a Linux environment on Windows with all the software tools
needed to build and test a chip design.

**Tool used:** WSL2 (Windows Subsystem for Linux) running Ubuntu, then
`apt` (Ubuntu's package installer) and manual downloads.

**What we did, in plain terms:** installed a small Linux computer that
lives inside Windows. Into it, we installed:
- **Icarus Verilog** — a program that can "run" a hardware design as a
  simulation, the same way you might run a video game to test it before
  shipping it, except here we're testing a chip design instead of a game.
- **A RISC-V cross-compiler (Zephyr SDK)** — a translator that turns
  human-readable code (C or assembly) into the raw binary instructions
  the RISC-V CPU actually understands. "Cross" because it runs on your
  Windows/WSL machine but produces code for a *different* kind of
  processor (RISC-V) than the one your laptop has.

**Output:** no visible "product" yet — this step just makes later steps
possible. Confirmed working by later successfully compiling and running
things with these tools.

---

## Step 2 — Getting the CPU design itself (`picorv32.v`)

**Goal:** get the actual "worker" — the CPU — as a design file, rather
than designing one from absolute scratch (which would take months).

**Tool used:** `wget` / `curl` (simple download tools) pulling directly
from GitHub, where PicoRV32 is an existing, well-tested, open-source CPU
design.

**What the file is, in plain terms:** `picorv32.v` is written in Verilog
— a language for describing digital circuits, not a normal programming
language. It doesn't get "run" like software; it describes the actual
wiring of a CPU. Think of it as a very precise blueprint that could,
in principle, be turned into a real physical chip.

The CPU talks to the outside world (memory, peripherals) through a small,
fixed set of signals:
- `mem_valid` — "I want to read or write something"
- `mem_ready` — the other side's answer: "done, here you go"
- `mem_addr` — which address it wants
- `mem_wdata` / `mem_wstrb` — data to write, and which bytes of it are real
- `mem_rdata` — data read back

This handshake (`valid`/`ready`) is the CPU's way of politely waiting its
turn — like a customer ringing a bell and waiting for the receptionist to
say "go ahead" before speaking.

**Output:** just a downloaded text file at this point — 3049 lines of
Verilog. Nothing runs yet.

---

## Step 3 — Building the RAM (`picorv32_ram.v`)

**Goal:** give the CPU a notebook to read instructions from and write
scratch data to.

**Tool used:** Claude wrote the Verilog file directly (no external
download — this is original code for the project).

**What it does, in plain pseudocode:**
```
every clock tick:
    if the CPU is asking for something (mem_valid) and we haven't
    answered yet:
        say "done" (mem_ready = 1)
        if it's a write: store the given data at the given address
        if it's a read: hand back whatever is stored there
```

It's an 8-kilobyte block of storage, organized as 2048 "slots" of 4 bytes
each (a "word"). The CPU addresses memory by byte, so the module does a
little math to figure out which slot a given address falls into.

**Output at this stage:** compiled cleanly with Icarus Verilog (a
syntax-only check — did the language get used correctly — no errors
printed, which in this tool means success). Not yet tested for *correct
behavior*, only that it's valid Verilog.

---

## Step 4 — The first bug: "unknown" memory

**Goal:** none yet — this was a debugging detour that happened once we
tried to actually run a test.

**Tool used:** Icarus Verilog simulation (`iverilog` to compile the
simulation, `vvp` to run it), plus Claude reproducing the exact same
setup in a separate sandbox to debug faster.

**What went wrong, in plain terms:** we assumed a brand-new notebook
(RAM) starts with every page blank (all zeros). In real simulation tools,
that's not automatic — a fresh notebook actually starts with pages full
of illegible scribbles ("unknown" values, shown as `x`), not blank pages.
So when the CPU tried to read its first instruction, it read gibberish
instead of the "blank page" we expected, and the test hung with a
timeout instead of behaving predictably.

**The fix, in pseudocode:**
```
at the very start of simulation:
    go through all 2048 notebook slots and write 0 into every one
```

**Output confirming the fix:** re-ran the same test; instead of a
timeout, it now reached the expected result (see Step 6) at a specific,
repeatable simulated time — proof the notebook really was blank this
time.

---

## Step 5 — Wiring the CPU to the RAM (`picorv32_top.v`, first version)

**Goal:** connect the "worker" (CPU) and the "notebook" (RAM) together
into one system.

**Tool used:** Claude-authored Verilog, no external tools — this is a
"wrapper" module whose only job is to instantiate (create one copy of)
the CPU and the RAM and connect their wires to each other.

**Key decisions made here, explained:**
- **Where does the worker start reading?** Set to address `0x00000000`
  — the very first slot in the notebook. This is a configuration
  parameter (`PROGADDR_RESET`) built into the CPU design.
- **Where's the "scratch pad" for temporary math?** (called the *stack*
  in programming — a section of memory used for temporary values).
  PicoRV32 defaults to pointing this at an address far outside our small
  8KB notebook, which would have caused the CPU to write into nonexistent
  memory. We had to explicitly set it (`STACKADDR`) to the top of our
  actual 8KB, so it stays inside real, usable notebook pages.

**Output:** compiled cleanly, all three files (CPU + RAM + this wrapper)
together — meaning every wire we connected actually matched up correctly
in name and size. No behavioral test yet.

---

## Step 6 — The first real test: "does the wiring actually work?"

**Goal:** actually run the simulated chip and check it behaves
sensibly, not just that it compiles.

**Tool used:** Icarus Verilog (`iverilog` + `vvp`), running a
"testbench" — a second Verilog file written specifically to test the
first one, not part of the chip itself.

**The clever trick used here:** since we just made sure the notebook
starts all blank (all zeros), and "all zeros" isn't a valid instruction
in the CPU's language, we can predict exactly what should happen: the
CPU should recognize it as gibberish and raise a red flag (called a
"trap").

**Pseudocode of the test:**
```
turn on the clock
hold the whole system in "reset" (paused) for a few ticks
release reset — CPU starts running
watch a signal called "trap"
if trap turns on within a reasonable time: PASS
    (this proves the CPU correctly detected the invalid instruction,
     which also proves the CPU-to-RAM communication is working —
     it had to successfully read something to know it was invalid)
if trap never turns on: FAIL, something in the wiring is stuck
```

**Output:** `PASS`, with the trap firing at a specific simulated
timestamp. This confirmed reset, clock, and CPU-to-RAM communication
were all functioning — even though the "test program" was just
accidental garbage (all zeros), not real code.

---

## Step 7 — Writing and compiling real firmware (`test.S`)

**Goal:** prove the CPU can actually execute real, intentional
instructions — not just correctly reject garbage.

**Tool used:** the RISC-V cross-compiler installed in Step 1
(specifically its assembler and linker), run from the WSL terminal.

**What the program does, in plain English (it's written in RISC-V
assembly, a very low-level human-readable form of the CPU's native
language):**
```
put the number 0xCAFEBABE into a scratchpad slot (a "register")
put the address 0x100 into another scratchpad slot
write the first number to the address in the second slot
    (i.e.: "save this number at this notebook page")
now just repeat "do nothing, go back to the start of this line"
    forever (so the program doesn't run off into random memory)
```

**The compilation pipeline, step by step:**
1. **Assemble + link** (`riscv64-zephyr-elf-gcc`) — turns the
   human-readable assembly text into an `.elf` file: a structured binary
   containing the actual machine code, organized with metadata about
   where everything goes in memory.
2. **Disassemble to check it** (`riscv64-zephyr-elf-objdump -d`) — the
   reverse operation, purely for us to *read* and confirm the compiler
   produced what we expected. This showed 4 real CPU instructions,
   correctly starting at address 0 as planned.

**Output:** a clean `.elf` file, and a disassembly listing matching our
intent exactly — confirms the compiler and linker script did their job
correctly, before we even try running it.

---

## Step 8 — Getting the program into simulated memory

**Goal:** the `.elf` file is a rich, structured format meant for real
hardware programmers — the simulator needs something much simpler: a
plain list of numbers to drop straight into the RAM array.

**Tools used:** `objcopy` (part of the cross-compiler toolkit) plus a
small custom Python script Claude wrote (`bin2hex.py`).

**Pipeline, in plain terms:**
1. `objcopy -O binary` — strips away all the `.elf` structure/metadata,
   leaving just the raw bytes of the program, back to back.
2. `bin2hex.py` — pseudocode:
   ```
   read the raw bytes, 4 at a time
   for each group of 4 bytes:
       treat them as one 32-bit number (matching how our RAM stores
       data, and matching the CPU's own byte-ordering convention)
       write that number out as one line of hex text
   ```
3. In the testbench, a built-in Verilog command called `$readmemh`
   reads that text file and pours it directly into the RAM's storage
   array before the simulation starts — like pre-writing the notebook
   pages before the worker walks in.

**Output:** a 5-line text file, each line one 32-bit hex number — and
those 5 numbers matched exactly the 5 machine-code words shown in the
Step 7 disassembly, confirming the conversion pipeline preserved the
program correctly.

---

## Step 9 — Running the real program in simulation

**Goal:** confirm the CPU actually executes this real program correctly
— not just that it doesn't crash, but that the *specific result*
(the stored number) is right.

**Tool used:** Icarus Verilog again, with a new testbench.

**Pseudocode of the test:**
```
before simulation starts: pour the program into RAM (Step 8)
release reset, let the CPU run for a generous number of clock ticks
after that time: look directly at RAM's notebook slot for address 0x100
if it holds the value 0xCAFEBABE: PASS
else: FAIL
```

**Output:** `PASS` — the exact value `0xcafebabe` was found sitting at
the correct address, confirming the CPU genuinely executed the load,
address-setup, and store instructions correctly, in order, and the
result is observably correct — not just "didn't crash."

---

## Step 10 — Building a receptionist: the address decoder

**Goal:** now that we want to add a second piece of equipment (UART, a
communication device — see Step 11), the CPU needs a way to reach either
the notebook (RAM) or the telephone (UART) depending on which "extension"
it dials.

**Tool used:** Claude-authored Verilog, no external tools.

**Design, in plain terms:** the CPU always says which address it wants.
We just look at that address:
```
if the address starts with 0x0... : this request is for RAM
if the address starts with 0x1... : this request is for UART
route the request to the right one, and route its answer back
```
This is pure "wiring logic" — no clock, no memory of its own, just
instant decision-making based on the address, the same way a
receptionist glances at which extension number you dialed and connects
you immediately, without needing to remember anything.

**Output:** compiled cleanly on its own. Since it doesn't yet have RAM or
UART attached to test against, this was a syntax-only check at this
stage — full behavioral testing came once it was wired into the rest of
the system (Step 12).

---

## Step 11 — Building the telephone: a real UART transmitter

**Goal:** give the CPU a way to send information *out* of the chip —
UART is the classic simple serial communication peripheral, the digital
equivalent of Morse code over a wire.

**Tool used:** Claude-authored Verilog, no external tools.

**How UART physically works, in plain terms:** instead of sending a
whole byte (8 bits) at once over 8 wires, UART sends it over a *single*
wire, one bit at a time, at a fixed, agreed-upon speed. To mark where a
byte begins and ends, it wraps the 8 real bits with a "start bit" (always
0) before them and a "stop bit" (always 1) after them — like an envelope
around a letter. The wire idles "high" (1) when nothing is being sent,
so a sudden drop to 0 is the signal "a new byte is coming."

**Pseudocode of the transmitter's behavior:**
```
line idles high (1) when nothing is happening

when the CPU writes a byte to send:
    hold the line low for one "bit-time"      (start bit)
    for each of the 8 bits, least-significant first:
        hold the line at that bit's value for one "bit-time"
    hold the line high for one "bit-time"      (stop bit)
    go back to idling high, ready for the next byte
```

There's also a small "status" the CPU can check first: a single flag
bit meaning "I'm idle and ready for a new byte" — so firmware knows not
to interrupt a transmission already in progress.

**Output:** compiled cleanly on its own, same situation as the decoder
— full behavioral testing came once wired into the complete system.

---

## Step 12 — Wiring it all together (`picorv32_top.v`, updated)

**Goal:** replace the simple "CPU directly to RAM" wiring from Step 5
with the full path: CPU → receptionist (decoder) → either RAM or UART.

**Tool used:** Claude rewrote the wrapper file; Icarus Verilog to
re-test everything.

**What changed, in plain terms:** the CPU's request signals now go into
the decoder instead of straight into RAM. The decoder's outputs go to
both RAM and UART. Both devices' answers come back through the decoder
to the CPU.

**Critical check performed here:** we re-ran *both* of the earlier
tests (Step 6's "garbage instruction trap" test, and Step 9's "store a
value" test) through this new, more complicated wiring — a technique
called **regression testing**: making sure that adding something new
didn't quietly break something that used to work.

**Output:** both earlier tests still printed `PASS`, with the exact
same timing as before — strong evidence the decoder correctly passes
RAM traffic through without altering it.

---

## Step 13 — Testing the telephone: sending a real letter

**Goal:** prove the UART transmitter genuinely sends the correct byte,
correctly framed — not just that the wiring compiles.

**Tools used:** the RISC-V cross-compiler (same pipeline as Step 7–8),
and Icarus Verilog with a purpose-built "listener" testbench.

**The firmware program, in plain English:**
```
point at the UART's address
keep checking its status flag until it says "ready"
write the letter 'A' (as a number, 0x41) to the UART's data register
loop forever
```

**The tricky part: how do you check a serial signal in simulation?**
The testbench itself has to act like a tiny UART *receiver* — the exact
mirror image of Step 11's transmitter logic:
```
wait for the line to drop from high to low     (start bit detected)
wait until the middle of that bit               (safest place to read
                                                   a signal, furthest
                                                   from any edge noise)
for each of the 8 expected data bits:
    wait one more "bit-time", then read the line's current value
after the 8th bit: wait one more "bit-time", confirm the line is
    back to high                                (stop bit, sanity check)
reassemble the 8 bits we read into one byte
compare it to the expected letter 'A' (0x41)
```

**Output:** the testbench printed `Decoded byte: 0x41` — an exact match
— with the stop bit correctly found high, meaning the framing was also
correct, not just the data. `PASS`.

---

## Where things stand right now

A complete, small computer system exists and has been *proven*, piece
by piece, in simulation:
- A real CPU, executing real instructions correctly
- A real block of memory, storing and returning data correctly
- A receptionist (decoder) correctly routing between two devices
- A real serial communication peripheral, sending correctly framed data

Every one of those claims has a passing, repeatable simulation test
behind it — not just "the code compiles."

## What's next

Two reasonable directions from here:
1. **Add GPIO and a Timer peripheral** — rounds out the peripheral set
   for this stage. The Timer specifically matters later because Zephyr
   (the RTOS this project is ultimately headed toward) needs a hardware
   timer to drive its task scheduler.
2. **Add a minimal C startup routine (`crt0.s`)** — lets this system run
   compiled C programs instead of only hand-written assembly, which is
   also a stepping stone toward eventually running Zephyr itself.
