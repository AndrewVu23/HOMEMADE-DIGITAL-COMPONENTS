module four_bank_sram #(parameter SRAM_DATA = 32, parameter MASK = 4)
(
    input logic clk, we,
    input logic [3:0] index,
    input logic [MASK-1:0] wmask,
    input logic [SRAM_DATA-1:0] wdata,
    output logic [SRAM_DATA-1:0] rdata
);
    logic [SRAM_DATA-1:0] sram_set [15:0]; // 16 sets for sram bank

    assign rdata = sram_set[index]; // read
    
    always_ff @(posedge clk) begin
        if (we) begin
            // bit assign for wmask logic (wmask chooses which part of a word to write)
            if (wmask[0]) sram_set[index][7:0]   <= wdata[7:0];
            if (wmask[1]) sram_set[index][15:8]  <= wdata[15:8];
            if (wmask[2]) sram_set[index][23:16] <= wdata[23:16];
            if (wmask[3]) sram_set[index][31:24] <= wdata[31:24];
        end
    end

endmodule