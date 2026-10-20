module picorv32_top (
    input  wire clk,
    input  wire resetn,
    output wire trap,
    output wire tx,          // UART serial output
    output wire [7:0] gpio_out,
    output wire [31:0] timer_out   // exposes current count for the testbench
);

    // CPU <-> decoder
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;

    // decoder <-> RAM
    wire        ram_valid;
    wire        ram_ready;
    wire [31:0] ram_rdata;

    // decoder <-> UART
    wire        uart_valid;
    wire        uart_ready;
    wire [31:0] uart_rdata;

    // decoder <-> GPIO
    wire        gpio_valid;
    wire        gpio_ready;
    wire [31:0] gpio_rdata;

    // decoder <-> Timer
    wire        timer_valid;
    wire        timer_ready;
    wire [31:0] timer_rdata;

    picorv32 #(
        .PROGADDR_RESET (32'h0000_0000),
        .STACKADDR      (32'h0000_1FFC),
        .ENABLE_IRQ     (0),
        .ENABLE_PCPI    (0)
    ) cpu (
        .clk       (clk),
        .resetn    (resetn),
        .trap      (trap),

        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),

        .mem_la_read  (),
        .mem_la_write (),
        .mem_la_addr  (),
        .mem_la_wdata (),
        .mem_la_wstrb (),

        .pcpi_valid (),
        .pcpi_insn  (),
        .pcpi_rs1   (),
        .pcpi_rs2   (),
        .pcpi_wr    (1'b0),
        .pcpi_rd    (32'b0),
        .pcpi_wait  (1'b0),
        .pcpi_ready (1'b0),

        .irq (32'b0),
        .eoi (),

        .trace_valid (),
        .trace_data  ()
    );

    picorv32_addr_decoder decoder (
        .mem_valid (mem_valid),
        .mem_addr  (mem_addr),
        .mem_ready (mem_ready),
        .mem_rdata (mem_rdata),

        .ram_valid (ram_valid),
        .ram_ready (ram_ready),
        .ram_rdata (ram_rdata),

        .uart_valid (uart_valid),
        .uart_ready (uart_ready),
        .uart_rdata (uart_rdata),

        .gpio_valid (gpio_valid),
        .gpio_ready (gpio_ready),
        .gpio_rdata (gpio_rdata),

        .timer_valid (timer_valid),
        .timer_ready (timer_ready),
        .timer_rdata (timer_rdata)
    );

    picorv32_ram #(
        .WORDS (2048)
    ) ram (
        .clk       (clk),
        .mem_valid (ram_valid),
        .mem_ready (ram_ready),
        .mem_wstrb (mem_wstrb),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (ram_rdata)
    );

    picorv32_uart_tx #(
        .CLKS_PER_BIT (4)
    ) uart (
        .clk       (clk),
        .resetn    (resetn),
        .mem_valid (uart_valid),
        .mem_ready (uart_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (uart_rdata),
        .tx        (tx)
    );

    picorv32_gpio gpio (
        .clk       (clk),
        .resetn    (resetn),
        .mem_valid (gpio_valid),
        .mem_ready (gpio_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (gpio_rdata),
        .gpio_out  (gpio_out)
    );

    picorv32_timer timer (
        .clk       (clk),
        .resetn    (resetn),
        .mem_valid (timer_valid),
        .mem_ready (timer_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (timer_rdata),
        .count     (timer_out)
    );

endmodule
