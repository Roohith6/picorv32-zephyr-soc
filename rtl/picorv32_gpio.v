// picorv32_gpio.v
// Minimal 8-bit GPIO OUTPUT peripheral, native mem interface.
// Deliberately output-only for a fast first pass -- input/direction
// control is a reasonable later addition, not needed yet.
//
// Register map (offset from GPIO base, see picorv32_addr_decoder.v):
//   0x0  GPIO_DATA (read/write): bits [7:0] drive gpio_out directly.
//        Reading it back returns the last value written.

module picorv32_gpio (
    input  wire        clk,
    input  wire        resetn,

    input  wire        mem_valid,
    output reg          mem_ready,
    input  wire [31:0]  mem_addr,
    input  wire [31:0]  mem_wdata,
    input  wire [3:0]   mem_wstrb,
    output reg  [31:0]  mem_rdata,

    output reg  [7:0]   gpio_out
);

    always @(posedge clk) begin
        if (!resetn) begin
            mem_ready <= 1'b0;
            gpio_out  <= 8'b0;
        end else begin
            mem_ready <= 1'b0;

            if (mem_valid && !mem_ready) begin
                mem_ready <= 1'b1;

                if (mem_wstrb != 4'b0000) begin
                    gpio_out <= mem_wdata[7:0];
                end else begin
                    mem_rdata <= {24'b0, gpio_out};
                end
            end
        end
    end

endmodule
