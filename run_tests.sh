cd /mnt/e/picorv32-zephyr-soc
RTL="rtl/picorv32.v rtl/picorv32_ram.v rtl/picorv32_uart_tx.v rtl/picorv32_gpio.v rtl/picorv32_timer.v rtl/picorv32_addr_decoder.v rtl/picorv32_top.v"
for tb in picorv32_top_tb picorv32_program_tb picorv32_uart_tb picorv32_c_test_tb picorv32_gpio_tb picorv32_timer_tb; do
  echo "--- $tb ---"
  iverilog -g2012 -o sim.out $RTL tb/$tb.v && vvp sim.out | tail -3
done
