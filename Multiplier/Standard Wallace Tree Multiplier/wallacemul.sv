module ha (
    input logic a, b,
    output logic s, c_out
);
    assign s = a ^ b;
    assign c_out = a & b;
endmodule

module fa (
    input logic a, b, c_in,
    output logic s, c_out,
);
    assign s = a ^ b ^ c_in;
    assign c_out = (a & b) || (a & c_in) || (b & c_in);
endmodule

module wallacemul (
    input signed [7:0] A, B,
    output signed [15:0] p
)
logic signed [7:0][7:0] pp;

genvar i;
genvar j;

generate
    for (i = 0; i < 8; i++) begin : row_loop
        for (j = 0; j < 8; j++) begin : col_loop
            assign pp[i][j] = A[j] & B[i];
        end
    end
endgenerate

generate
