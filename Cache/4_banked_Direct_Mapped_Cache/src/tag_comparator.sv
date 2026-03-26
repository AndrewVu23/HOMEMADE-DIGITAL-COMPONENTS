module tag_comparator #(parameter TAG_COMPARATOR = 24)
(
    input logic [TAG_COMPARATOR-1:0] req_tag,
    input logic [TAG_COMPARATOR-1:0] store_tag,
    input logic valid,
    
    output logic hit
);
    assign hit = valid && (req_tag == store_tag);

endmodule