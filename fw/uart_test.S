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
