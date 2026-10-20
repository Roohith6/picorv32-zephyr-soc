# CMakeLists.txt
# Uses Zephyr's default RISC-V linker script to start. A custom
# linker.ld is only needed if this default doesn't fit our memory map
# -- something we'll find out from the first real build attempt rather
# than assuming up front.

zephyr_include_directories(.)

set(SOC_LINKER_SCRIPT ${ZEPHYR_BASE}/include/zephyr/arch/riscv/common/linker.ld CACHE INTERNAL "")
