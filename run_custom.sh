cd /mnt/e/picorv32-zephyr-soc
GCC=~/zephyr-sdk-1.0.1/riscv64-zephyr-elf/bin/riscv64-zephyr-elf

echo "1. Compiling C code..."
${GCC}-gcc -c fw/custom_app.c -o fw/custom_app.o -march=rv32i -mabi=ilp32 -O0 -ffreestanding -nostdlib
${GCC}-gcc -nostdlib -nostartfiles -T fw/c_test.ld -o fw/custom_app.elf fw/crt0.o fw/custom_app.o -march=rv32i -mabi=ilp32

echo "2. Converting binary to hex..."
${GCC}-objcopy -O binary fw/custom_app.elf fw/custom_app.bin
python3 fw/bin2hex.py fw/custom_app.bin fw/custom_app.hex

echo "3. Compiling Verilog hardware..."
iverilog -g2012 -o sim_custom.out rtl/picorv32.v rtl/picorv32_ram.v rtl/picorv32_uart_tx.v rtl/picorv32_gpio.v rtl/picorv32_timer.v rtl/picorv32_addr_decoder.v rtl/picorv32_top.v tb/picorv32_print_tb.v

echo "4. Running Simulation!"
echo "======================================"
vvp sim_custom.out
echo "======================================"
