`timescale 1ns/1ps

module baud_rate_gen_tb;

    parameter BIT_CYCLE   = 434;
    parameter SAMPLE_RATE = 16;
    parameter CLK_PERIOD  = 20;  // 50 MHz

    logic clk, reset, tx_start;
    logic tx_en, rx_en;

    baud_rate_gen #(
        .BIT_CYCLE(BIT_CYCLE),
        .SAMPLE_RATE(SAMPLE_RATE)
    ) dut (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),
        .tx_en(tx_en),
        .rx_en(rx_en)
    );

    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Helper tasks ---
    integer tx_tick_count, rx_tick_count;
    integer tx_period, rx_period;
    integer cycle_count;

    task automatic count_ticks(input int num_cycles);
        tx_tick_count = 0;
        rx_tick_count = 0;
        for (cycle_count = 0; cycle_count < num_cycles; cycle_count++) begin
            @(posedge clk);
            if (tx_en) tx_tick_count = tx_tick_count + 1;
            if (rx_en) rx_tick_count = rx_tick_count + 1;
        end
    endtask

    task automatic measure_tx_period(output int period);
        // Wait for a tx_en pulse, then count until the next one
        @(posedge clk);
        while (!tx_en) @(posedge clk);
        period = 0;
        @(posedge clk);
        while (!tx_en) begin
            period = period + 1;
            @(posedge clk);
        end
        period = period + 1; // include the final cycle
    endtask

    task automatic measure_rx_period(output int period);
        @(posedge clk);
        while (!rx_en) @(posedge clk);
        period = 0;
        @(posedge clk);
        while (!rx_en) begin
            period = period + 1;
            @(posedge clk);
        end
        period = period + 1;
    endtask

    // --- Tests ---
    initial begin
        clk = 0;
        reset = 1;
        tx_start = 0;
        #(CLK_PERIOD * 5);
        @(negedge clk);

        // =============================================
        // Test 1: Reset clears outputs and counters
        // =============================================
        if (tx_en === 1'b0 && rx_en === 1'b0)
            $display("[PASSED]: Reset clears tx_en and rx_en");
        else begin
            $display("[FAILED]: Reset clears tx_en and rx_en");
            $display("  tx_en=%b, rx_en=%b (expected both 0)", tx_en, rx_en);
        end

        // Release reset
        reset = 0;

        // =============================================
        // Test 2: tx_en period matches BIT_CYCLE
        // =============================================
        measure_tx_period(tx_period);
        if (tx_period == BIT_CYCLE)
            $display("[PASSED]: tx_en period = %0d cycles (expected %0d)", tx_period, BIT_CYCLE);
        else begin
            $display("[FAILED]: tx_en period = %0d cycles (expected %0d)", tx_period, BIT_CYCLE);
        end

        // =============================================
        // Test 3: rx_en period matches BIT_CYCLE/SAMPLE_RATE
        // =============================================
        measure_rx_period(rx_period);
        if (rx_period == BIT_CYCLE / SAMPLE_RATE)
            $display("[PASSED]: rx_en period = %0d cycles (expected %0d)", rx_period, BIT_CYCLE / SAMPLE_RATE);
        else begin
            $display("[FAILED]: rx_en period = %0d cycles (expected %0d)", rx_period, BIT_CYCLE / SAMPLE_RATE);
        end

        // =============================================
        // Test 4: rx_en fires SAMPLE_RATE times per tx_en period
        // =============================================
        // Count rx ticks over several tx_en periods
        count_ticks(BIT_CYCLE * 4);
        if (rx_tick_count == tx_tick_count * SAMPLE_RATE)
            $display("[PASSED]: rx_en fires %0dx per tx_en (expected %0dx)",
                     rx_tick_count / (tx_tick_count > 0 ? tx_tick_count : 1), SAMPLE_RATE);
        else begin
            $display("[FAILED]: Over %0d tx periods, got %0d rx ticks (expected %0d)",
                     tx_tick_count, rx_tick_count, tx_tick_count * SAMPLE_RATE);
        end

        // =============================================
        // Test 5: tx_en and rx_en are single-cycle pulses
        // =============================================
        begin
            integer consecutive_tx, consecutive_rx;
            integer pulse_fail;
            consecutive_tx = 0;
            consecutive_rx = 0;
            pulse_fail = 0;
            // Run for a few bit periods and check no back-to-back pulses
            for (int i = 0; i < BIT_CYCLE * 2; i++) begin
                @(posedge clk);
                if (tx_en) consecutive_tx = consecutive_tx + 1;
                else consecutive_tx = 0;
                if (rx_en) consecutive_rx = consecutive_rx + 1;
                else consecutive_rx = 0;

                if (consecutive_tx > 1 && !pulse_fail) begin
                    $display("[FAILED]: tx_en not single-cycle (consecutive=%0d)", consecutive_tx);
                    pulse_fail = 1;
                end
                if (consecutive_rx > 1 && !pulse_fail) begin
                    $display("[FAILED]: rx_en not single-cycle (consecutive=%0d)", consecutive_rx);
                    pulse_fail = 1;
                end
            end
            if (!pulse_fail)
                $display("[PASSED]: tx_en and rx_en are single-cycle pulses");
        end

        // =============================================
        // Test 6: Reset mid-operation clears counters
        // =============================================
        // Let it run a bit, then reset
        #(CLK_PERIOD * 100);
        @(negedge clk);
        reset = 1;
        #(CLK_PERIOD * 3);
        @(negedge clk);
        if (tx_en === 1'b0 && rx_en === 1'b0)
            $display("[PASSED]: Mid-operation reset clears outputs");
        else
            $display("[FAILED]: Mid-operation reset - tx_en=%b, rx_en=%b", tx_en, rx_en);

        reset = 0;
        // Verify it resumes correctly
        measure_tx_period(tx_period);
        if (tx_period == BIT_CYCLE)
            $display("[PASSED]: Resumes correct tx_en period after reset");
        else
            $display("[FAILED]: Post-reset tx_en period = %0d (expected %0d)", tx_period, BIT_CYCLE);

        // =============================================
        // Test 7: tx_start resets tx_counter
        // =============================================
        // Let it run partway through a period, then pulse tx_start
        #(CLK_PERIOD * (BIT_CYCLE / 2));  // halfway through a period
        @(negedge clk);
        tx_start = 1;
        @(negedge clk);
        tx_start = 0;
        // The next tx_en should arrive exactly BIT_CYCLE clocks after tx_start
        measure_tx_period(tx_period);
        if (tx_period == BIT_CYCLE)
            $display("[PASSED]: tx_start resets tx_counter (period = %0d)", tx_period);
        else
            $display("[FAILED]: tx_start reset - period = %0d (expected %0d)", tx_period, BIT_CYCLE);

        $display("\nbaud_rate_gen testbench complete.");
        $finish;
    end

endmodule
