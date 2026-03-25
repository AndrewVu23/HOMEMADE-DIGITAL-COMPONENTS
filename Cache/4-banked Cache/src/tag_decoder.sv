// 24-bit tag + dirty + valid. From now on I will refer to this combination as metadata
module tag_decoder #(parameter TAG_DECODER = 26)
(
    input logic clk, rst, we,
    input logic [3:0] index,
    input logic [TAG_DECODER-1:0] wdata,

    output logic [TAG_DECODER-1:0] rdata
);
    logic [TAG_DECODER-1:0] tag_set [15:0]; // 16 sets of metadata for the sram

    assign rdata = tag_set[index]; // read

    always_ff @(posedge clk) begin
        if (rst) begin
            // clear only valid and dirty bits; tag data doesn't matter while valid=0
            for (int i = 0; i < 16; i++) begin
                tag_set[i][25:24] <= 2'b00; // {dirty, valid} = 0
            end
        end 
        
        else if (we) begin
            tag_set[index] <= wdata; // write
        end
    end

endmodule