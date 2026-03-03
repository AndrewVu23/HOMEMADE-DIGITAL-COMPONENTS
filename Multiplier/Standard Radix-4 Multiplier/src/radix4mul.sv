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

    // A_next is N+1 bits since we have to account for overflowing when doing
    // addition between A and M, with M = MIN(int) (edge case)
    logic signed [N:0] A_next; 
    
    assign P = {A_reg, Q_reg};

    always_comb begin
        case({Q_reg[1], Q_reg[0], Q_ref})
            3'b000: A_next = $signed({A_reg[N-1], A_reg}); // Sign extend A_reg
            3'b001: A_next = $signed(A_reg) + $signed(M_reg); // Exit string of 1s -> Add
            3'b010: A_next = $signed(A_reg) + $signed(M_reg); // Only one 1 -> Add
            3'b011: A_next = $signed(A_reg) + $signed(M_reg << 1); // Exit string of 1s -> 2Add
            3'b100: A_next = $signed(A_reg) - $signed(M_reg << 1); // Enter string of 1s -> 2Sub
            3'b101: A_next = $signed(A_reg) - $signed(M_reg); // Exit and Enter string of 1s -> 2Sub + Add = Sub
            3'b110: A_next = $signed(A_reg) - $signed(M_reg); //Enter string of 1s -> Sub
            3'b111: A_next = $signed({A_reg[N-1], A_reg}); // Sign extend A_reg
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
                    A_reg <= {A_next[N], A_next[N-1:2];
                    Q_reg <= {A_next[1], A_next[0], Q_reg[N-1:2]};
                    Q_ref <= Q_reg[1];
                
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
