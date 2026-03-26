module cache_controller #(parameter TAG_COMPARATOR = 24, parameter TAG_DECODER = 26)
(
    input  logic clk, rst,
    input  logic req, we, hit, dirty, valid, mem_ready,
    input  logic [TAG_COMPARATOR-1:0] req_tag,

    output logic tag_we, alloc_fill, data_we, mem_req, mem_we, stall,
    output logic [TAG_DECODER-1:0] tag_wdata
);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        WRITEBACK = 2'b01,
        ALLOCATE = 2'b10
    } state_t;
    
    state_t state, next_state;

    // state changes happen on the clock edge (in sync with the cpu)
    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else state <= next_state;
    end

    // the cache needs to read & write & send signals instantly to other components in that state
    always_comb begin
        tag_we = 0;
        tag_wdata = 0;
        alloc_fill = 0;
        data_we = 0;
        mem_req = 0;
        mem_we = 0;
        stall = 0;
        next_state = state;

        case (state)
            IDLE: begin
                if (req) begin

                    // clean hit
                    if (hit) begin
                        stall = 0;

                        // write hit
                        if (we) begin
                            tag_we = 1;

                            // write new data to the cache locally, haven't updated to the main memory => dirty = 1
                            tag_wdata = {1'b1, 1'b1, req_tag}; 
                            data_we = 1;
                            alloc_fill = 0; 
                        end
                    end

                    // miss
                    else begin
                        stall = 1;

                        //dirt miss
                        if (valid && dirty) begin
                            next_state = WRITEBACK;
                        end

                        // clean miss
                        else begin
                            next_state = ALLOCATE;
                        end
                    end
                end
            end

            WRITEBACK: begin

                // hold cpu to evict the old block
                stall = 1;
                mem_req = 1;
                mem_we = 1;
                
                if (mem_ready) begin
                    next_state = ALLOCATE; 
                end
            end

            ALLOCATE: begin

                // hold cpu to wait for the new block
                stall = 1;
                mem_req = 1;
                mem_we = 0;
                
                if (mem_ready) begin

                    // writing 128-bit blocks to the 4 banks
                    data_we = 1;
                    alloc_fill = 1;
                    tag_we = 1;
                    tag_wdata = {1'b0, 1'b1, req_tag}; // data is updated => dirty = 0
                    
                    // go back to IDLE. the cpu will ask for the same address again in the next cycle,
                    // which will be a hit this time
                    next_state = IDLE;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

endmodule