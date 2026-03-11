module main_mem_mux #(parameter ADDRESS = 32)
(
    input logic we,
    input logic [ADDRESS-1:0] old_data, new_data,
    output logic [ADDRESS-1:0] data
);
    assign data = we ? old_data : new_data;
endmodule