`timescale 1ns/1ps

module write_demux_tb;
    parameter SRAM_DATA = 32;
    parameter MASK = 4;

    logic alloc_fill;
    logic data_we;
    logic [1:0] index;
    logic [MASK-1:0] wmask;
    logic [SRAM_DATA-1:0] wdata;
    logic [4*SRAM_DATA-1:0] mem_rdata;
    logic [SRAM_DATA-1:0] bank_0, bank_1, bank_2, bank_3;
    logic [MASK-1:0] bank0_wmask, bank1_wmask, bank2_wmask, bank3_wmask;
    logic bank0_we, bank1_we, bank2_we, bank3_we;

    write_demux #(SRAM_DATA, MASK) dut (.*);

    initial begin
        alloc_fill = 0;
        data_we = 0;
        index = 0;
        wmask = 0;
        wdata = 0;
        mem_rdata = 0;
        
        #10;

        // Test 1: No Write (data_we = 0)
        data_we = 0;
        alloc_fill = 0;
        index = 2'b10; // cpu is requesting to write bank 2, but we = 0
        wdata = 32'hFFFFFFFF;
        wmask = 4'b1111;
        #10;
        
        if (bank0_we == 0 && bank1_we == 0 && bank2_we == 0 && bank3_we == 0)
            $display("[PASSED]: Test 1 (data_we=0). No banks enabled.");
        else
            $display("[FAILED]: Test 1. A bank WE is incorrectly high.");
        
        // Test 2: Write Hit to Bank 2 (index = 2'b10)
        data_we = 1;
        alloc_fill = 0;
        index = 2'b10; // word 2
        wdata = 32'hCAFEBABE;
        wmask = 4'b0011; // lower halfword
        #10;
        
        if (bank2_we == 1 && bank2_wmask == 4'b0011 && bank_2 == 32'hCAFEBABE &&
            bank0_we == 0 && bank1_we == 0 && bank3_we == 0)
            $display("[PASSED]: Test 2 (Write Hit to Bank 2). Demux correct.");
        else
            $display("[FAILED]: Test 2. Write Not routed properly.");

        // Test 3: Write Hit to Bank 0 (index = 2'b00)
        data_we = 1;
        alloc_fill = 0;
        index = 2'b00; // word 0
        wdata = 32'h87654321;
        wmask = 4'b1111; // full word
        #10;
        
        if (bank0_we == 1 && bank0_wmask == 4'b1111 && bank_0 == 32'h87654321 &&
            bank1_we == 0 && bank2_we == 0 && bank3_we == 0)
            $display("[PASSED]: Test 3 (Write Hit to Bank 0). Demux correct.");
        else
            $display("[FAILED]: Test 3. Write Not routed properly.");

        // Test 4: Cache Miss Fill (alloc_fill = 1)
        data_we = 1;
        alloc_fill = 1;
        index = 2'b01;  // should be ignored during a Miss fill
        wdata = 32'h00000000;
        wmask = 4'b0000;
        
        // memory returns a full 128-bit block (words 3, 2, 1, 0)
        // {bank3, bank2, bank1, bank0}
        mem_rdata = 128'hDDDDCCCC_BBBBAAAA_99998888_77776666; 
        #10;
        
        if (bank0_we == 1 && bank1_we == 1 && bank2_we == 1 && bank3_we == 1 &&
            bank0_wmask == 4'b1111 && bank3_wmask == 4'b1111 &&
            bank_0 == 32'h77776666 &&
            bank_1 == 32'h99998888 &&
            bank_2 == 32'hBBBBAAAA &&
            bank_3 == 32'hDDDDCCCC)
            $display("[PASSED]: Test 4 (Miss Fill). 128-bit block successfully broadcast to all 4 banks.");
        else
            $display("[FAILED]: Test 4. Miss Fill not broadcasting properly.");

        $display("write_demux Testbench Completed.");
        $finish;
    end
endmodule
