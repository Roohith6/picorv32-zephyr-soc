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
