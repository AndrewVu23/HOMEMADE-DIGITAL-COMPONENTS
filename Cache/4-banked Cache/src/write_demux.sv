module write_demux #(parameter SRAM_DATA = 32, parameter MASK = 4)
(
    input  logic alloc_fill, 
    input  logic data_we,
    input  logic [1:0] index,
    input  logic [MASK-1:0] wmask,
    input  logic [SRAM_DATA-1:0] wdata,
    input  logic [4*SRAM_DATA-1:0] mem_rdata,
    output logic [SRAM_DATA-1:0] bank_0, bank_1, bank_2, bank_3,
    output logic [MASK-1:0] bank0_wmask, bank1_wmask, bank2_wmask, bank3_wmask,
    output logic bank0_we, bank1_we, bank2_we, bank3_we
);
    always_comb begin
        // default 
        bank0_we = 1'b0; bank1_we = 1'b0; bank2_we = 1'b0; bank3_we = 1'b0;
        bank_0 = '0; bank_1 = '0; bank_2 = '0; bank_3 = '0;
        bank0_wmask = '0; bank1_wmask = '0; bank2_wmask = '0; bank3_wmask = '0;

        if (data_we) begin
            if (alloc_fill) begin // write miss
                bank0_we = 1'b1; bank1_we = 1'b1; bank2_we = 1'b1; bank3_we = 1'b1; // enable all banks to get new data

                // overwrite the old mask  -> allowing all parts of the word to be overwritten
                // for clarity -> four_bank_sram.sv. if a bit of wmask is 1 -> can be overwritten
                bank0_wmask = '1; bank1_wmask = '1; bank2_wmask = '1; bank3_wmask = '1;

                bank_0 = mem_rdata[31:0];
                bank_1 = mem_rdata[63:32];
                bank_2 = mem_rdata[95:64];
                bank_3 = mem_rdata[127:96];
            end

            else begin // write hit -> write to 1 bank only
                case(index)
                    2'b00: begin bank0_we = 1'b1; bank_0 = wdata; bank0_wmask = wmask; end
                    2'b01: begin bank1_we = 1'b1; bank_1 = wdata; bank1_wmask = wmask; end
                    2'b10: begin bank2_we = 1'b1; bank_2 = wdata; bank2_wmask = wmask; end
                    2'b11: begin bank3_we = 1'b1; bank_3 = wdata; bank3_wmask = wmask; end
                endcase
            end
        end
    end

endmodule