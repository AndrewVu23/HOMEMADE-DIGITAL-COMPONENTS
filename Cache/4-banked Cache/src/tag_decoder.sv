// 24-bit tag + dirty + valid. From now on I will refer to this combination as metadata
module tag_decoder #(parameter TAG_DECODER = 26)
(
    input logic clk, we,
    input logic [3:0] index,
    input logic [TAG_DECODER-1:0] wdata,
    output logic [TAG_DECODER-1:0] rdata
);
    logic [TAG_DECODER-1:0] tag_set [15:0]; // 16 sets of metadata for the sram
    
    assign rdata = tag_set[index]; // read

    always_ff @(posedge clk) begin
        if (we) begin
            tag_set[index] <= wdata; // write
        end
    end

endmodule