module baud_rate_gen #(parameter BIT_CYCLE = 434, parameter SAMPLE_RATE = 16)
(
    input logic clk, reset, tx_start,
    output logic tx_en, rx_en
);
logic [9:0] tx_counter;
logic [5:0] rx_counter;

always_ff @(posedge clk) begin
    if (reset) begin
        tx_counter <= 0;
        rx_counter <= 0;
        tx_en <= 0;
        rx_en <= 0;
    end
    else begin
        // Reset tx_counter when a new transmission begins so the
        // start bit is exactly BIT_CYCLE clocks long
        if (tx_start) begin
            tx_counter <= 0;
            tx_en <= 0;
        end
        else if (tx_counter == BIT_CYCLE - 1) begin
            tx_counter <= 0;
            tx_en <= 1'b1;
        end
        else begin
            tx_en <= 0;
            tx_counter <= tx_counter + 1'b1;
        end

        if (rx_counter == BIT_CYCLE/SAMPLE_RATE - 1) begin
            rx_counter <= 0;
            rx_en <= 1'b1;
        end
        else begin
            rx_en <= 0;
            rx_counter <= rx_counter + 1'b1;
        end
    end
end
endmodule