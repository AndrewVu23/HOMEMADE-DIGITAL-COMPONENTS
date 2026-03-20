`timescale 1ns/1ps

module TX_tb;

    parameter N          = 8;
    parameter BIT_CYCLE  = 32;   // must be multiple of 16 (SAMPLE_RATE)
    parameter CLK_PERIOD = 20;   // 50 MHz

    logic clk, reset;
    logic tx_en, write_en;
    logic [N-1:0] tx_in;
    logic tx_out, busy;

    // Instantiate a baud generator with the small divisor
    // Wire write_en to tx_start so the counter resets on each new TX
    baud_rate_gen #(.BIT_CYCLE(BIT_CYCLE)) baud_gen (
        .clk(clk), .reset(reset),
        .tx_start(write_en),
        .tx_en(tx_en), .rx_en()
    );

    TX #(.N(N)) dut (
        .clk(clk), .reset(reset),
        .tx_en(tx_en),
        .write_en(write_en),
        .tx_in(tx_in),
        .tx_out(tx_out),
        .busy(busy)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // Capture a full UART frame from tx_out (start + 8 data + stop = 10 bits)
    task automatic capture_frame(output logic [9:0] frame);
        integer i;
        // Wait for start bit (falling edge of tx_out)
        @(posedge clk);
        while (tx_out !== 1'b0) @(posedge clk);

        // We're at the start bit. Sample at each tx_en tick.
        for (i = 0; i < 10; i++) begin
            // Wait for the tx_en tick that marks this bit
            @(posedge clk);
            while (!tx_en) @(posedge clk);
            frame[i] = tx_out;
        end
    endtask

    task automatic send_byte(input logic [N-1:0] data);
        @(negedge clk);
        tx_in    = data;
        write_en = 1;
        @(negedge clk);
        write_en = 0;
    endtask

    task automatic check_frame(
        input logic [N-1:0] expected_data,
        input string test_name
    );
        logic [9:0] frame;
        logic [N-1:0] received_data;
        logic start_bit, stop_bit;

        capture_frame(frame);

        start_bit     = frame[0];
        received_data = frame[N:1];
        stop_bit      = frame[9];

        if (start_bit === 1'b0 && received_data === expected_data && stop_bit === 1'b1)
            $display("[PASSED]: %s - sent 0x%02h, frame=[S:%b D:%08b P:%b]",
                     test_name, expected_data, start_bit, received_data, stop_bit);
        else begin
            $display("[FAILED]: %s", test_name);
            $display("  Expected: start=0, data=0x%02h, stop=1", expected_data);
            $display("  Got:      start=%b, data=0x%02h (%08b), stop=%b",
                     start_bit, received_data, received_data, stop_bit);
        end
    endtask

    initial begin
        clk      = 0;
        reset    = 1;
        write_en = 0;
        tx_in    = '0;
        #(CLK_PERIOD * 5);
        @(negedge clk);

        // =============================================
        // Test 1: Reset state - tx_out high, not busy
        // =============================================
        if (tx_out === 1'b1 && busy === 1'b0)
            $display("[PASSED]: Reset state - tx_out=1, busy=0");
        else
            $display("[FAILED]: Reset state - tx_out=%b, busy=%b", tx_out, busy);

        reset = 0;
        // No need to sync to tx_en — write_en resets the baud counter
        @(posedge clk);

        // =============================================
        // Test 2: Transmit 0x55 (alternating bits)
        // =============================================
        send_byte(8'h55);
        check_frame(8'h55, "TX 0x55 (alternating 01010101)");

        // Wait for idle
        @(posedge clk);
        while (busy) @(posedge clk);

        // =============================================
        // Test 3: Transmit 0xAA (alternating bits inverted)
        // =============================================
        send_byte(8'hAA);
        check_frame(8'hAA, "TX 0xAA (alternating 10101010)");

        @(posedge clk);
        while (busy) @(posedge clk);
        while (!tx_en) @(posedge clk);

        // =============================================
        // Test 4: Transmit 0x00 (all zeros)
        // =============================================
        send_byte(8'h00);
        check_frame(8'h00, "TX 0x00 (all zeros)");

        @(posedge clk);
        while (busy) @(posedge clk);
        while (!tx_en) @(posedge clk);

        // =============================================
        // Test 5: Transmit 0xFF (all ones)
        // =============================================
        send_byte(8'hFF);
        check_frame(8'hFF, "TX 0xFF (all ones)");

        @(posedge clk);
        while (busy) @(posedge clk);
        while (!tx_en) @(posedge clk);

        // =============================================
        // Test 6: Transmit 0xA3 (arbitrary pattern)
        // =============================================
        send_byte(8'hA3);
        check_frame(8'hA3, "TX 0xA3 (10100011)");

        @(posedge clk);
        while (busy) @(posedge clk);

        // =============================================
        // Test 7: busy flag goes high during TX
        // =============================================
        @(negedge clk);
        tx_in    = 8'h42;
        write_en = 1;
        @(negedge clk);
        write_en = 0;
        // busy should be high now
        @(negedge clk);
        if (busy === 1'b1)
            $display("[PASSED]: busy=1 during transmission");
        else
            $display("[FAILED]: busy=%b during transmission (expected 1)", busy);

        // Wait for completion
        while (busy) @(posedge clk);
        @(negedge clk);
        if (busy === 1'b0)
            $display("[PASSED]: busy=0 after transmission complete");
        else
            $display("[FAILED]: busy=%b after transmission (expected 0)", busy);

        // =============================================
        // Test 8: Idle line stays high
        // =============================================
        begin
            integer idle_ok;
            idle_ok = 1;
            for (int i = 0; i < BIT_CYCLE * 3; i++) begin
                @(posedge clk);
                if (tx_out !== 1'b1) idle_ok = 0;
            end
            if (idle_ok)
                $display("[PASSED]: tx_out stays high when idle");
            else
                $display("[FAILED]: tx_out went low while idle");
        end

        $display("\nTX testbench complete.");
        $finish;
    end

endmodule
