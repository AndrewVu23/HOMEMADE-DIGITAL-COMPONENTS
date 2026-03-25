module cache_top #(
    parameter TAG_DECODER = 26, 
    parameter TAG_COMPARATOR = 24, 
    parameter SRAM_DATA = 32, 
    parameter MASK = 4, 
    parameter ADDRESS = 32
)
(
    // cpu interface
    input  logic clk, rst,
    input  logic req,
    input  logic we,
    input  logic [ADDRESS-1:0]   addr,
    input  logic [SRAM_DATA-1:0] wdata,
    input  logic [MASK-1:0]      wmask,
    
    output logic [SRAM_DATA-1:0] rdata,
    output logic hit,
    output logic stall,

    // main memory interface
    input  logic [4*SRAM_DATA-1:0] mem_rdata,
    input  logic mem_ready,

    output logic mem_req,
    output logic mem_we,
    output logic [ADDRESS-1:0]   mem_addr,
    output logic [4*SRAM_DATA-1:0] mem_wdata
);
    // address slices
    logic [23:0] req_tag;
    logic [3:0]  index;
    logic [1:0]  word_sel;
    
    assign req_tag = addr[31:8];
    assign index = addr[7:4];
    assign word_sel = addr[3:2];

    // tag sram outputs
    logic [TAG_DECODER-1:0] tag_rdata;
    logic dirty, valid;
    logic [23:0] stored_tag;
    
    assign stored_tag = tag_rdata[23:0];
    assign valid = tag_rdata[24];
    assign dirty = tag_rdata[25];

    // cache controller outputs
    logic tag_we;
    logic [25:0] tag_wdata;
    logic alloc_fill;
    logic data_we;

    // write demux outputs (to the 4 banks)
    logic [SRAM_DATA-1:0] bank0_wdata, bank1_wdata, bank2_wdata, bank3_wdata;
    logic bank0_we, bank1_we, bank2_we, bank3_we;
    logic [MASK-1:0] bank0_wmask, bank1_wmask, bank2_wmask, bank3_wmask;

    // data bank outputs
    logic [SRAM_DATA-1:0] bank0_rdata, bank1_rdata, bank2_rdata, bank3_rdata;

    // multi-bank writeback routing
    assign mem_wdata = {bank3_rdata, bank2_rdata, bank1_rdata, bank0_rdata};

    // 1. tag sram (stores metadata for the 16 sets)
    tag_decoder #(TAG_DECODER) tag_sram_module (
        .clk (clk),
        .rst (rst),
        .we (tag_we),
        .index (index),
        .wdata (tag_wdata),
        .rdata (tag_rdata)
    );

    // 2. tag comparator (asynchronously checks for a hit)
    tag_comparator #(TAG_COMPARATOR) tag_comparator_module (
        .req_tag (req_tag),
        .store_tag (stored_tag),
        .valid (valid),
        .hit (hit)
    );

    // 3. cache controller fsm (the brains)
    cache_controller #(TAG_COMPARATOR, TAG_DECODER) controller_module (
        .clk (clk),
        .rst (rst),
        .req (req),
        .we (we),
        .hit (hit),
        .dirty (dirty),
        .valid (valid),
        .req_tag (req_tag),
        .mem_ready (mem_ready),
        
        .tag_we (tag_we),
        .tag_wdata (tag_wdata),
        .alloc_fill (alloc_fill),
        .data_we (data_we),
        .mem_req (mem_req),
        .mem_we (mem_we),
        .stall (stall)
    );

    // 4. write demux (routes writes to correct banks)
    write_demux #(SRAM_DATA, MASK) write_demux_module (
        .alloc_fill (alloc_fill),
        .data_we (data_we),
        .index (word_sel),
        .wmask (wmask),
        .wdata (wdata),
        .mem_rdata (mem_rdata),
        
        .bank_0 (bank0_wdata), .bank_1 (bank1_wdata), .bank_2 (bank2_wdata), .bank_3 (bank3_wdata),
        .bank0_we (bank0_we), .bank1_we (bank1_we), .bank2_we (bank2_we), .bank3_we (bank3_we),
        .bank0_wmask (bank0_wmask), .bank1_wmask (bank1_wmask), .bank2_wmask (bank2_wmask), .bank3_wmask (bank3_wmask)
    );

    // 5. 4-banked sram
    // bank 0
    four_bank_sram #(SRAM_DATA, MASK) bank0_module (
        .clk (clk),
        .we (bank0_we),
        .index (index),
        .wmask (bank0_wmask),
        .wdata (bank0_wdata),
        .rdata (bank0_rdata)
    );

    // bank 1
    four_bank_sram #(SRAM_DATA, MASK) bank1_module (
        .clk (clk),
        .we (bank1_we),
        .index (index),
        .wmask (bank1_wmask),
        .wdata (bank1_wdata),
        .rdata (bank1_rdata)
    );

    // bank 2
    four_bank_sram #(SRAM_DATA, MASK) bank2_module (
        .clk (clk),
        .we (bank2_we),
        .index (index),
        .wmask (bank2_wmask),
        .wdata (bank2_wdata),
        .rdata (bank2_rdata)
    );

    // bank 3
    four_bank_sram #(SRAM_DATA, MASK) bank3_module (
        .clk (clk),
        .we (bank3_we),
        .index (index),
        .wmask (bank3_wmask),
        .wdata (bank3_wdata),
        .rdata (bank3_rdata)
    );

    // 6. read mux (selects the correct word from the 4 banks for the CPU)
    read_mux #(SRAM_DATA) read_mux_module (
        .sel (word_sel),
        .bank_0 (bank0_rdata),
        .bank_1 (bank1_rdata),
        .bank_2 (bank2_rdata),
        .bank_3 (bank3_rdata),
        .rdata (rdata)
    );

    // 7. main memory address mux (eviction vs allocation routing)
    main_mem_mux #(ADDRESS) main_mem_mux_module (
        .we (mem_we),
        .old_data ({stored_tag, index, 4'b0000}), 
        .new_data ({addr[31:4], 4'b0000}),        
        .data (mem_addr)
    );

endmodule