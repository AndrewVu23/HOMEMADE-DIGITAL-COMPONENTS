module TX #(parameter N = 8)(
    input logic clk, reset, tx_en, write_en,
    input logic [N-1:0] tx_in,
    output logic tx_out, busy
);
logic [N-1:0] data_temp;
logic [3:0] index;

typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
state_t state;

always_ff @(posedge clk) begin
    if (reset) begin
        state <= IDLE;
        tx_out <= 1'b1;
        data_temp <= '0;
        index <= '0;
    end
    else begin
        case(state)
            IDLE: begin
                tx_out <= 1'b1;
                if (write_en) begin
                    state <= START;
                    index <= 3'b0;
                    data_temp <= tx_in;
                end
            end
            START: begin
                tx_out <= 1'b0;
                if (tx_en) begin
                    state <= DATA;
                    index <= 0;
                end
            end
            DATA: begin
                tx_out <= data_temp[index];
                if (tx_en) begin
                    if (index == N-1) state <= STOP;
                    else index <= index + 1'b1;
                end
            end
            STOP: begin
                tx_out <= 1'b1;
                if (tx_en) state <= IDLE;
            end
            default: state <= IDLE;
        endcase
    end
end

assign busy = (state != IDLE);

endmodule