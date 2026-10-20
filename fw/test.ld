/* test.ld
 * Places code starting at 0x00000000, matching picorv32_top's
 * PROGADDR_RESET, within an 8KB region matching picorv32_ram's
 * default WORDS=2048 depth.
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
    .data : { *(.data*) } > RAM
}
