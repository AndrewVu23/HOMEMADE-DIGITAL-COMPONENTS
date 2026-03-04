module radix4mul #(parameter N = 32, parameter COUNT = 15)
(
    input logic clk, rst, en,
    input logic [N-1:0] M, Q, // M = multiplicand, Q = multiplier
    output logic [2*N-1:0] P // P = product
);
    typedef enum logic [1:0] {IDLE, CALC, STOP} state_t;
    state_t state;

    logic signed [N-1:0] M_reg, Q_reg, A_reg; // A = Accumulator (storing upper bits of the product)
    logic Q_ref; // LSB of Q
    logic [$clog2(N):0] count; 

    // A_next is N+2 bits (34 bits) to handle +/- 2M without overflow.
    logic signed [N+1:0] A_next;
    assign P = {A_reg, Q_reg};

    // If the second-last number of the register is 1, when we shift right by 1 bit, the number would become negative.
    // Therefore, we need a 34-bit register to match the accummulator and handle the shifting case.
    logic signed [N+1:0] M_ext;
    assign M_ext = $signed(M_reg);

    always_comb begin
        // Perform math in 34-bit signed space to prevent overflow of +/- 2M
        case({Q_reg[1], Q_reg[0], Q_ref})
            3'b001:  A_next = $signed(A_reg) + M_ext;
            3'b010:  A_next = $signed(A_reg) + M_ext;
            3'b011:  A_next = $signed(A_reg) + (M_ext <<< 1);
            3'b100:  A_next = $signed(A_reg) - (M_ext <<< 1);
            3'b101:  A_next = $signed(A_reg) - M_ext;
            3'b110:  A_next = $signed(A_reg) - M_ext;
            default: A_next = $signed(A_reg);
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            M_reg <= 0;
            Q_reg <= 0;
            A_reg <= 0;
            Q_ref <= 0;
            count <= 0;
            state <= IDLE;
        end

        else begin
            case(state)
                IDLE: begin
                    M_reg <= M;
                    Q_reg <= Q;
                    A_reg <= 0;
                    Q_ref <= 0;
                    count <= 0;
                    if (en) state <= CALC;
                    else state <= IDLE;
                end

                CALC: begin
                    // 2-bit Arithmetic Shift Right
                    Q_ref <= Q_reg[1];
                    A_reg <= A_next[N+1:2];
                    Q_reg <= {A_next[1:0], Q_reg[N-1:2]};
                
                    count <= count + 1;
                    if (count == COUNT) state <= STOP; // Stop after evaluating all 32 bits
                end

                STOP: begin
                    if (en) state <= IDLE;
                    else state <= STOP;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
