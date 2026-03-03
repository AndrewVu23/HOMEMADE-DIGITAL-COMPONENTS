module radix2mul #(parameter N = 32)
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

    // A_next is N+1 bits since we have to account for overflowing when doing
    // addition between A and M, with M = MIN(int) (edge case)
    logic signed [N:0] A_next; 
    
    assign P = {A_reg, Q_reg};

    always_comb begin
        case({Q_reg[0], Q_ref})
            2'b01: A_next = $signed(A_reg) + $signed(M_reg); // Exit string of 1s -> Add
            2'b10: A_next = $signed(A_reg) - $signed(M_reg); // Enter string of 1s -> Sub
            default: A_next = $signed({A_reg[N-1], A_reg}); // Sign extend A_reg
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
                    
                    // Arithmetic Shift Right of {A_next, Q_reg}
                    A_reg <= A_next[N:1];
                    Q_reg <= {A_next[0], Q_reg[N-1:1]};
                    Q_ref <= Q_reg[0];
                    
                    count <= count + 1;
                    if (count == N - 1) state <= STOP; // Stop after evaluating all 32 bits
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
