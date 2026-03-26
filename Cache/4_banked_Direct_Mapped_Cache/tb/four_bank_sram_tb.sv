`timescale 1ns/1ps

module four_bank_sram_tb;
    parameter SRAM_DATA = 32;
    parameter MASK = 4;

    logic clk;
    logic we;
    logic [3:0] index;
    logic [MASK-1:0] wmask;
    logic [SRAM_DATA-1:0] wdata;
    logic [SRAM_DATA-1:0] rdata;

    four_bank_sram #(SRAM_DATA, MASK) dut (.*);

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        we = 0;
        index = 0;
        wmask = 0;
        wdata = 0;
        
        #10;
        
        // Test 1: Write Full Word to Index 5
        we = 1;
        index = 5;
        wdata = 32'hDEADBEEF;
        wmask = 4'b1111; // enable all bytes
        #10;
        
        // Test 2: Read Full Word from Index 5
        we = 0;
        index = 5;
        wdata = 32'h00000000; // reset wdata to prove it's reading from SRAM
        wmask = 4'b0000;
        #10;
        
        if (rdata == 32'hDEADBEEF) $display("[PASSED]: Test 1 & 2 (Full Write/Read). Data: %h", rdata);
        else $display("[FAILED]: Test 1 & 2. Expected DEADBEEF, Got %h", rdata);
        
        // Test 3: Write Partial Word (Lowest Byte Only) to Index 5
        we = 1;
        index = 5;
        wdata = 32'h000000AA; // overwrite EF with AA
        wmask = 4'b0001; // enable only the bottom byte (bits 7:0)
        #10;
        
        // Test 4: Read Index 5 after Partial Write
        we = 0;
        #10;
        
        if (rdata == 32'hDEADBEAA) $display("[PASSED]: Test 3 & 4 (Partial Byte Write). Data: %h", rdata);
        else $display("[FAILED]: Test 3 & 4. Expected DEADBEAA, Got %h", rdata);

        // Test 5: Write Half-Word (Top 2 Bytes) to Index 10
        // 1. write a fresh full word
        we = 1;
        index = 10;
        wdata = 32'h11112222;
        wmask = 4'b1111;
        #10;
        
        // 2. overwrite just the top 16 bits
        we = 1;
        wdata = 32'h99990000; // only the 9999 should go through
        wmask = 4'b1100; // enable only top two bytes (bits 31:16)
        #10;
        
        we = 0;
        #10;
        
        if (rdata == 32'h99992222) $display("[PASSED]: Test 5 (Half-Word Top Write). Data: %h", rdata);
        else $display("[FAILED]: Test 5. Expected 99992222, Got %h", rdata);
        
        $display("four_bank_sram Testbench Completed.");
        $finish;
    end
endmodule
