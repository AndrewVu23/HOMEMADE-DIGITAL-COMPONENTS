module ha (
    input logic a, b,
    output logic s, c_out
);
    assign s = a ^ b;
    assign c_out = a & b;
endmodule

module fa (
    input logic a, b, c_in,
    output logic s, c_out
);
    assign s = a ^ b ^ c_in;
    assign c_out = (a & b) || (a & c_in) || (b & c_in);
endmodule

module wallacemul (
    input [7:0] A, B,
    output [15:0] p
);
logic [7:0][7:0] pp; // An array that holds all the partial products

genvar i, j;

generate
    for (i = 0; i < 8; i++) begin : row_loop
        for (j = 0; j < 8; j++) begin : col_loop
            assign pp[i][j] = A[j] & B[i];
        end
    end
endgenerate

logic [15:0] row0_padded, row1_padded, row2_padded, row3_padded, row4_padded, row5_padded, row6_padded, row7_padded;

assign row0_padded = {8'b0, pp[0]};
assign row1_padded = {7'b0, pp[1], 1'b0};
assign row2_padded = {6'b0, pp[2], 2'b0};
assign row3_padded = {5'b0, pp[3], 3'b0};
assign row4_padded = {4'b0, pp[4], 4'b0};
assign row5_padded = {3'b0, pp[5], 5'b0};
assign row6_padded = {2'b0, pp[6], 6'b0};
assign row7_padded = {1'b0, pp[7], 7'b0};

logic [15:0] sum1, sum2, sum3, sum4, sum5;
logic [16:0] carry1, carry2, carry3, carry4, carry5;
logic [15:0] final_sum;
logic [16:0] final_carry;

assign carry1[0] = 1'b0;
assign carry2[0] = 1'b0;
assign carry3[0] = 1'b0;
assign carry4[0] = 1'b0;
assign carry5[0] = 1'b0;
assign final_carry[0] = 1'b0;

genvar k;

generate
    for (k = 0; k < 16; k++) begin : column_loop_stage1_zone1
        fa fa1(
            .a(row0_padded[k]),
            .b(row1_padded[k]),
            .c_in(row2_padded[k]),
            .s(sum1[k]),
            .c_out(carry1[k+1])
        );
    end
    
    for (k = 0; k < 16; k++) begin : column_loop_stage1_zone2
        fa fa2(
            .a(row3_padded[k]),
            .b(row4_padded[k]),
            .c_in(row5_padded[k]),
            .s(sum2[k]),
            .c_out(carry2[k+1])
        );
    end

    for (k = 0; k < 16; k++) begin : column_loop_stage2_zone1
        fa fa3(
            .a(sum1[k]),
            .b(carry1[k]),
            .c_in(sum2[k]),
            .s(sum3[k]),
            .c_out(carry3[k+1])
        );
    end

    for (k = 0; k < 16; k++) begin : column_loop_stage2_zone2
        fa fa4(
            .a(carry2[k]),
            .b(row6_padded[k]),
            .c_in(row7_padded[k]),
            .s(sum4[k]),
            .c_out(carry4[k+1])
        );
    end

    for (k = 0; k < 16; k++) begin : column_loop_stage3_zone1
        fa fa5(
            .a(sum3[k]),
            .b(carry3[k]),
            .c_in(sum4[k]),
            .s(sum5[k]),
            .c_out(carry5[k+1])
        );
    end

    for (k = 0; k < 16; k++) begin : column_loop_final
        fa fa6(
            .a(sum5[k]),
            .b(carry5[k]),
            .c_in(carry4[k]),
            .s(final_sum[k]),
            .c_out(final_carry[k+1])
        );
    end
endgenerate

assign p = final_sum + final_carry[15:0];

endmodule
