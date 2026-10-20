/* test.S
 * Minimal bare-metal test program for Stage A bring-up.
 *
 * Stores 0xCAFEBABE to RAM address 0x100, then loops forever.
 * Purpose: prove the CPU can actually execute instructions (not just
 * correctly detect an illegal one, which is all the previous smoke
 * test showed).
 */

.section .text
.global _start

_start:
    li      x1, 0xCAFEBABE      /* value to store */
    li      x2, 0x00000100      /* target address */
    sw      x1, 0(x2)           /* store word */

loop:
    j       loop                /* spin here so the testbench can
                                    inspect memory at leisure */
