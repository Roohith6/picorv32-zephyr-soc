// picorv32_addr_decoder.v
// Combinational address decoder: demuxes mem_valid to the addressed
// peripheral, muxes mem_ready/mem_rdata back to the CPU.
//
// Address map:
//   0x0000_0000 - 0x0000_1FFF : RAM
//   0x1000_0000 - 0x1000_00FF : UART
//   0x2000_0000 - 0x2000_00FF : GPIO
//   0x3000_0000 - 0x3000_00FF : Timer
//
// mem_addr/mem_wdata/mem_wstrb are NOT routed through this module --
// they fan out directly from the CPU to every peripheral in the top
// module. Only mem_valid (demux) and mem_ready/mem_rdata (mux) pass
// through here, since address decode is the only thing that differs
// per peripheral.
//
// Known simplification: an access to an unmapped address never
// completes (mem_ready stays low forever, CPU stalls). Fine for a
// controlled bring-up; a production SoC would want a decode-error
// timeout here.

module picorv32_addr_decoder (
    input  wire        mem_valid,
    input  wire [31:0] mem_addr,
    output wire         mem_ready,
    output wire [31:0]  mem_rdata,

    output wire        ram_valid,
    input  wire        ram_ready,
    input  wire [31:0] ram_rdata,

    output wire        uart_valid,
    input  wire        uart_ready,
    input  wire [31:0] uart_rdata,

    output wire        gpio_valid,
    input  wire        gpio_ready,
    input  wire [31:0] gpio_rdata,

    output wire        timer_valid,
    input  wire        timer_ready,
    input  wire [31:0] timer_rdata
);

    wire sel_ram   = (mem_addr[31:28] == 4'h0);
    wire sel_uart  = (mem_addr[31:28] == 4'h1);
    wire sel_gpio  = (mem_addr[31:28] == 4'h2);
    wire sel_timer = (mem_addr[31:28] == 4'h3);

    assign ram_valid   = mem_valid && sel_ram;
    assign uart_valid  = mem_valid && sel_uart;
    assign gpio_valid  = mem_valid && sel_gpio;
    assign timer_valid = mem_valid && sel_timer;

    assign mem_ready = sel_ram   ? ram_ready   :
                        sel_uart  ? uart_ready  :
                        sel_gpio  ? gpio_ready  :
                        sel_timer ? timer_ready :
                        1'b0;

    assign mem_rdata = sel_ram   ? ram_rdata   :
                        sel_uart  ? uart_rdata  :
                        sel_gpio  ? gpio_rdata  :
                        sel_timer ? timer_rdata :
                        32'hxxxxxxxx;

endmodule
