`timescale 1ns/1ps

module cache_controller_tb;
    parameter TAG_COMPARATOR = 24;
    parameter TAG_DECODER = 26;
    
    logic clk, rst;
    logic req, we, hit, dirty, valid, mem_ready;
    logic tag_we, alloc_fill, data_we, mem_req, mem_we, stall;
    logic [TAG_COMPARATOR-1:0] req_tag;
    logic [TAG_DECODER-1:0] tag_wdata;

    cache_controller #(
        .TAG_COMPARATOR(TAG_COMPARATOR),
        .TAG_DECODER(TAG_DECODER)
    ) dut (.*);

    always #5 clk = ~clk;

    task check_outputs(
        input logic exp_tag_we, exp_alloc_fill, exp_data_we, 
        input logic exp_mem_req, exp_mem_we, exp_stall,
        input string test_name
    );
        begin
            if (tag_we === exp_tag_we && alloc_fill === exp_alloc_fill && 
                data_we === exp_data_we && mem_req === exp_mem_req && 
                mem_we === exp_mem_we && stall === exp_stall) begin
                $display("[PASSED]: %s", test_name);
            end else begin
                $display("[FAILED]: %s", test_name);
                $display("Expected: tag_we=%b, alloc_fill=%b, data_we=%b, mem_req=%b, mem_we=%b, stall=%b", 
                         exp_tag_we, exp_alloc_fill, exp_data_we, exp_mem_req, exp_mem_we, exp_stall);
                $display("Got: tag_we=%b, alloc_fill=%b, data_we=%b, mem_req=%b, mem_we=%b, stall=%b", 
                         tag_we, alloc_fill, data_we, mem_req, mem_we, stall);
            end
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        req = 0; we = 0; hit = 0; dirty = 0; valid = 0; mem_ready = 0;
        req_tag = 24'hAABBCC;
        
        #15;
        rst = 0;
        
        // align stimulus to negative clock edge to avoid race conditions with posedge updates
        @(negedge clk);
        
        // Test 1: IDLE - No Request
        req = 0;
        #1;
        check_outputs(0, 0, 0, 0, 0, 0, "Test 1: IDLE (No Req) - All signals 0");
        
        @(negedge clk);
        // Test 2: Read Hit
        req = 1;
        we = 0;
        hit = 1;
        #1;
        check_outputs(0, 0, 0, 0, 0, 0, "Test 2: Read Hit - No stall, no writes");
        
        @(negedge clk);
        // Test 3: Write Hit
        req = 1;
        we = 1;
        hit = 1;
        #1;
        check_outputs(1, 0, 1, 0, 0, 0, "Test 3: Write Hit - tag_we=1, data_we=1, stall=0");
        if (tag_wdata === {1'b1, 1'b1, 24'hAABBCC}) 
            $display("[PASSED]: Test 3b - Tag wdata correctly formatted for write hit");
        else 
            $display("[FAILED]: Test 3b - Tag wdata formatting failed");
        
        @(negedge clk);
        // Test 4: Clean Miss (Transition to ALLOCATE)
        req = 1; we = 0;
        hit = 0;
        valid = 0;
        dirty = 0;

        #1;
        check_outputs(0, 0, 0, 0, 0, 1, "Test 4a: Clean Miss Detected - Stall asserted");
        
        @(negedge clk);
        #1;
        check_outputs(0, 0, 0, 1, 0, 1, "Test 4b: ALLOCATE State - mem_req=1, mem_we=0, stall=1");
        
        @(negedge clk);
        mem_ready = 1;
        #1;
        check_outputs(1, 1, 1, 1, 0, 1, "Test 4c: ALLOCATE Finished - Arrays Written (tag_we=1, data_we=1, alloc=1)");
        if (tag_wdata === {1'b0, 1'b1, 24'hAABBCC})
            $display("[PASSED]: Test 4d - Tag wdata correctly formatted for mem fill");
        else 
            $display("[FAILED]: Test 4d - Tag wdata formatting failed");
        
        @(negedge clk);
        mem_ready = 0;
        hit = 1; 
        #1;
        check_outputs(0, 0, 0, 0, 0, 0, "Test 4e: Retry Read Hit - CPU resumes");

        @(negedge clk);
        // Test 5: Dirty Miss (Transition WRITEBACK -> ALLOCATE -> IDLE)
        req = 1;
        hit = 0;
        valid = 1;
        dirty = 1;
        #1;
        check_outputs(0, 0, 0, 0, 0, 1, "Test 5a: Dirty Miss Detected - Stall asserted");
        
        @(negedge clk);
        #1;
        check_outputs(0, 0, 0, 1, 1, 1, "Test 5b: WRITEBACK state - mem_req=1, mem_we=1 (EVICT)");
        
        @(negedge clk);
        mem_ready = 1;
        
        @(negedge clk);
        mem_ready = 0;
        #1;
        check_outputs(0, 0, 0, 1, 0, 1, "Test 5c: ALLOCATE state - fetching new block");
        
        @(negedge clk);
        mem_ready = 1;
        #1;
        check_outputs(1, 1, 1, 1, 0, 1, "Test 5d: ALLOCATE Finished - Data written to cache");
        
        @(negedge clk);
        mem_ready = 0;
        hit = 1;
        #1;
        check_outputs(0, 0, 0, 0, 0, 0, "Test 5e: Retry Hit - CPU resumes");

        $display("cache_controller Testbench Completed.");
        $finish;
    end
endmodule
