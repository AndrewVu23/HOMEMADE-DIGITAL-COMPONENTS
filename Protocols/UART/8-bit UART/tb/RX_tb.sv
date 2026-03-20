`timescale 1ns/1ps

module RX_tb;

    parameter N           = 8;
    parameter BIT_CYCLE   = 32;   // must be multiple of 16 (SAMPLE_RATE)
    parameter SAMPLE_RATE = 16;
    parameter CLK_PERIOD  = 20;   // 50 MHz

    logic clk, reset, ready_clr;
    logic rx_en;
    logic rx_in;
    logic ready;
    logic [N-1:0] rx_out;

    // Baud generator for rx_en ticks
    baud_rate_gen #(
        .BIT_CYCLE(BIT_CYCLE),
        .SAMPLE_RATE(SAMPLE_RATE)
    ) baud_gen (
        .clk(clk), .reset(reset),
        .tx_start(1'b0),
        .tx_en(), .rx_en(rx_en)
    );

    RX #(.N(N), .SAMPLE_RATE(SAMPLE_RATE)) dut (
        .clk(clk), .reset(reset),
        .ready_clr(ready_clr),
        .rx_en(rx_en),
        .rx_in(rx_in),
        .ready(ready),
        .rx_out(rx_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // Drive a UART frame onto rx_in at the correct baud rate
    // Each bit held for exactly BIT_CYCLE clock cycles
    task automatic drive_frame(input logic [N-1:0] data);
        integer i;
        // Start bit
        rx_in = 1'b0;
        repeat (BIT_CYCLE) @(posedge clk);
        // Data bits (LSB first)
        for (i = 0; i < N; i++) begin
            rx_in = data[i];
            repeat (BIT_CYCLE) @(posedge clk);
        end
        // Stop bit
        rx_in = 1'b1;
        repeat (BIT_CYCLE) @(posedge clk);
    endtask

    // Drive a frame with a bad stop bit (framing error)
    task automatic drive_frame_bad_stop(input logic [N-1:0] data);
        integer i;
        rx_in = 1'b0;
        repeat (BIT_CYCLE) @(posedge clk);
        for (i = 0; i < N; i++) begin
            rx_in = data[i];
            repeat (BIT_CYCLE) @(posedge clk);
        end
        // Bad stop bit = LOW
        rx_in = 1'b0;
        repeat (BIT_CYCLE) @(posedge clk);
        rx_in = 1'b1;  // return to idle
    endtask

    // Drive a glitch (short low pulse, not a real start bit)
    task automatic drive_glitch();
        rx_in = 1'b0;
        // Hold for less than half a bit period worth of rx_en ticks
        repeat (BIT_CYCLE / SAMPLE_RATE * 2) @(posedge clk);
        rx_in = 1'b1;
        repeat (BIT_CYCLE * 2) @(posedge clk);
    endtask

    task automatic check_rx(
        input logic [N-1:0] expected,
        input string test_name
    );
        if (ready === 1'b1 && rx_out === expected)
            $display("[PASSED]: %s - received 0x%02h", test_name, rx_out);
        else begin
            $display("[FAILED]: %s", test_name);
            $display("  Expected: ready=1, data=0x%02h", expected);
            $display("  Got:      ready=%b, data=0x%02h", ready, rx_out);
        end
    endtask

    initial begin
        clk       = 0;
        reset     = 1;
        ready_clr = 0;
        rx_in     = 1'b1;  // idle high
        #(CLK_PERIOD * 5);
        @(negedge clk);

        // =============================================
        // Test 1: Reset state
        // =============================================
        if (ready === 1'b0 && rx_out === '0)
            $display("[PASSED]: Reset state - ready=0, rx_out=0");
        else
            $display("[FAILED]: Reset state - ready=%b, rx_out=0x%02h", ready, rx_out);

        reset = 0;
        // Let baud gen stabilize
        repeat (BIT_CYCLE) @(posedge clk);

        // =============================================
        // Test 2: Receive 0x55
        // =============================================
        drive_frame(8'h55);
        // Wait a bit for ready
        repeat (BIT_CYCLE) @(posedge clk);
        check_rx(8'h55, "RX 0x55 (01010101)");

        // Clear ready
        @(negedge clk);
        ready_clr = 1;
        @(negedge clk);
        ready_clr = 0;
        @(negedge clk);
        if (ready === 1'b0)
            $display("[PASSED]: ready_clr clears ready flag");
        else
            $display("[FAILED]: ready_clr did not clear ready (ready=%b)", ready);

        repeat (BIT_CYCLE) @(posedge clk);

        // =============================================
        // Test 3: Receive 0xAA
        // =============================================
        drive_frame(8'hAA);
        repeat (BIT_CYCLE) @(posedge clk);
        check_rx(8'hAA, "RX 0xAA (10101010)");
        @(negedge clk); ready_clr = 1;
        @(negedge clk); ready_clr = 0;

        repeat (BIT_CYCLE) @(posedge clk);

        // =============================================
        // Test 4: Receive 0x00
        // =============================================
        drive_frame(8'h00);
        repeat (BIT_CYCLE) @(posedge clk);
        check_rx(8'h00, "RX 0x00 (all zeros)");
        @(negedge clk); ready_clr = 1;
        @(negedge clk); ready_clr = 0;

        repeat (BIT_CYCLE) @(posedge clk);

        // =============================================
        // Test 5: Receive 0xFF
        // =============================================
        drive_frame(8'hFF);
        repeat (BIT_CYCLE) @(posedge clk);
        check_rx(8'hFF, "RX 0xFF (all ones)");
        @(negedge clk); ready_clr = 1;
        @(negedge clk); ready_clr = 0;

        repeat (BIT_CYCLE) @(posedge clk);

        // =============================================
        // Test 6: Glitch rejection
        // =============================================
        drive_glitch();
        if (ready === 1'b0)
            $display("[PASSED]: Glitch rejected (ready stayed low)");
        else
            $display("[FAILED]: Glitch not rejected (ready=%b)", ready);

        repeat (BIT_CYCLE) @(posedge clk);

        // =============================================
        // Test 7: Framing error (bad stop bit) - data dropped
        // =============================================
        ready_clr = 1;
        @(negedge clk);
        ready_clr = 0;
        @(negedge clk);
        drive_frame_bad_stop(8'hBE);
        repeat (BIT_CYCLE) @(posedge clk);
        if (ready === 1'b0)
            $display("[PASSED]: Framing error - data correctly dropped (ready=0)");
        else
            $display("[FAILED]: Framing error - ready=%b (expected 0)", ready);

        repeat (BIT_CYCLE) @(posedge clk);

        // =============================================
        // Test 8: Normal receive after framing error
        // =============================================
        drive_frame(8'h42);
        repeat (BIT_CYCLE) @(posedge clk);
        check_rx(8'h42, "RX 0x42 after framing error recovery");

        $display("\nRX testbench complete.");
        $finish;
    end

endmodule
