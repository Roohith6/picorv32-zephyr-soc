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
