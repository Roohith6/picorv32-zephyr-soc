`timescale 1ns / 1ps

module picorv32_print_tb;

    localparam CLK_PERIOD    = 10;
    localparam CLKS_PER_BIT  = 4;
    localparam BIT_PERIOD    = CLK_PERIOD * CLKS_PER_BIT;

    reg clk = 0;
    reg resetn = 0;
    wire trap;
    wire tx;
    wire [7:0] gpio_out;

    always #5 clk = ~clk;

    picorv32_top dut (
        .clk       (clk),
        .resetn    (resetn),
        .trap      (trap),
        .tx        (tx),
        .gpio_out  (gpio_out)
    );

    initial begin
        // Load the custom hex file
        $readmemh("fw/custom_app.hex", dut.ram.mem);
        
        // Wait 10 clocks then bring CPU out of reset
        repeat (10) @(posedge clk);
        resetn = 1;
        
        // Stop the simulation after enough time for the program to run
        // Increased time to allow the full C program (and slow UART) to finish
        #5000000;
        $display("\n[Simulation Finished]");
        $finish;
    end

    // UART decoding logic - prints characters directly to the simulator console
    reg [7:0] rx_byte;
    integer i;
    
    always begin
        @(negedge tx); // Wait for start bit (tx goes low)
        if (resetn) begin
            #(BIT_PERIOD / 2); // Wait half a bit period to sample in the middle
            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_PERIOD);
                rx_byte[i] = tx; // Read bit
            end
            #(BIT_PERIOD); // Stop bit
            $write("%c", rx_byte); // Print character directly to terminal
        end
    end
    
    // Monitor GPIO changes and print them out
    always @(gpio_out) begin
        if (resetn)
            $display("\n[%0t] GPIO Pins changed to: 0x%h", $time, gpio_out);
    end

endmodule
