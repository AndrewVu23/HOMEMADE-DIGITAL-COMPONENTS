module read_mux #(parameter SRAM_DATA = 32)
(
    input logic [1:0] sel,
    input logic [SRAM_DATA-1:0] bank_0, bank_1, bank_2, bank_3,
    output logic [SRAM_DATA-1:0] rdata
);
    always_comb begin
        case(sel)
            2'b00: rdata = bank_0;
            2'b01: rdata = bank_1;
            2'b10: rdata = bank_2;
            2'b11: rdata = bank_3;
            default: rdata = 32'b0;
        endcase
    end

endmodule