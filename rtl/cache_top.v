// =============================================================================
// File: cache_top.v
// Description: Top-level Module for 4KB 2-Way Set-Associative Cache
//              Integrates Cache Controller, Tag Arrays, Data Arrays, and LRU Logic.
// Architecture:
//   - Total Capacity: 4096 Bytes (4KB)
//   - Line Size: 16 Bytes (4 words x 32 bits = 128 bits)
//   - Associativity: 2-Way Set-Associative (128 sets)
//   - Write Policy: Write-Back with Write-Allocate
//   - Replacement Policy: LRU (Least Recently Used)
// Course: Computer Architecture (Kien Truc May Tinh)
// =============================================================================

`timescale 1ns / 1ps
`include "cache_defines.vh"

module cache_top #(
    parameter ADDR_WIDTH      = `ADDR_WIDTH,
    parameter DATA_WIDTH      = `DATA_WIDTH,
    parameter LINE_WIDTH      = `LINE_WIDTH,
    parameter TAG_WIDTH       = `TAG_WIDTH,
    parameter INDEX_WIDTH     = `INDEX_WIDTH,
    parameter WORD_SEL_WIDTH  = `WORD_SEL_WIDTH,
    parameter NUM_SETS        = `NUM_SETS
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // -------------------------------------------------------------------------
    // CPU Interface
    // -------------------------------------------------------------------------
    input  wire                   cpu_req,    // Memory access request strobe
    input  wire                   cpu_we,     // 0: Read, 1: Write
    input  wire [ADDR_WIDTH-1:0]  cpu_addr,   // 32-bit byte address
    input  wire [DATA_WIDTH-1:0]  cpu_wdata,  // 32-bit data to write
    output wire [DATA_WIDTH-1:0]  cpu_rdata,  // 32-bit data read from cache
    output wire                   cpu_ready,  // 1: Transaction complete, 0: Stall CPU

    // -------------------------------------------------------------------------
    // Main Memory (DRAM) Interface
    // -------------------------------------------------------------------------
    output wire                   mem_req,    // Memory access request strobe
    output wire                   mem_we,     // 0: Read line, 1: Write line
    output wire [ADDR_WIDTH-1:0]  mem_addr,   // 32-bit block address (16-byte aligned)
    output wire [LINE_WIDTH-1:0]  mem_wdata,  // 128-bit line to write back
    input  wire [LINE_WIDTH-1:0]  mem_rdata,  // 128-bit line fetched from DRAM
    input  wire                   mem_ready,  // 1: DRAM ready strobe

    // -------------------------------------------------------------------------
    // Telemetry / Debug Status Outputs
    // -------------------------------------------------------------------------
    output wire                   hit_out,
    output wire                   miss_out,
    output wire [2:0]             state_out
);

    // -------------------------------------------------------------------------
    // Internal Signals & Interconnects
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0]     latched_addr;
    wire [DATA_WIDTH-1:0]     latched_wdata;
    wire                      latched_we;
    wire [LINE_WIDTH-1:0]     refill_line;
    wire                      sel_refill_data;

    // Set & Word Index selection
    wire [INDEX_WIDTH-1:0]    current_index = (state_out == `STATE_IDLE) ? 
                                              cpu_addr[`INDEX_MSB:`INDEX_LSB] : 
                                              latched_addr[`INDEX_MSB:`INDEX_LSB];

    wire [WORD_SEL_WIDTH-1:0] current_word_idx = (state_out == `STATE_IDLE) ? 
                                                 cpu_addr[`WORD_SEL_MSB:`WORD_SEL_LSB] : 
                                                 latched_addr[`WORD_SEL_MSB:`WORD_SEL_LSB];

    // Tag and Data Array outputs
    wire [TAG_WIDTH-1:0]      tag0, tag1;
    wire                      valid0, valid1;
    wire                      dirty0, dirty1;
    wire [LINE_WIDTH-1:0]     line_out0, line_out1;
    wire [DATA_WIDTH-1:0]     word_out0, word_out1;

    // Write enables from Controller
    wire tag_we0, dirty_we0, dirty_in0, line_we0, word_we0;
    wire tag_we1, dirty_we1, dirty_in1, line_we1, word_we1;

    // LRU signals
    wire lru_update;
    wire lru_access_way;
    wire lru_bit;
    wire victim_way;

    // -------------------------------------------------------------------------
    // Tag Comparison & Hit Detection Logic
    // -------------------------------------------------------------------------
    wire [TAG_WIDTH-1:0] req_tag = latched_addr[`TAG_MSB:`TAG_LSB];
    wire hit0 = valid0 && (tag0 == req_tag);
    wire hit1 = valid1 && (tag1 == req_tag);
    wire hit  = hit0 || hit1;
    wire hit_way = hit1; // 0 for Way 0, 1 for Way 1

    assign hit_out  = (state_out == `STATE_COMPARE_TAG) && hit;
    assign miss_out = (state_out == `STATE_COMPARE_TAG) && !hit;

    // -------------------------------------------------------------------------
    // CPU Read Data Multiplexer
    // -------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] hit_rdata = (hit0) ? word_out0 : word_out1;

    reg [DATA_WIDTH-1:0] refill_rdata;
    always @(*) begin
        case (latched_addr[`WORD_SEL_MSB:`WORD_SEL_LSB])
            2'b00: refill_rdata = refill_line[31:0];
            2'b01: refill_rdata = refill_line[63:32];
            2'b10: refill_rdata = refill_line[95:64];
            2'b11: refill_rdata = refill_line[127:96];
            default: refill_rdata = refill_line[31:0];
        endcase
    end

    assign cpu_rdata = (sel_refill_data) ? refill_rdata : hit_rdata;

    // -------------------------------------------------------------------------
    // Module Instantiations
    // -------------------------------------------------------------------------

    // Way 0 Tag Array
    tag_array #(
        .NUM_SETS(NUM_SETS),
        .INDEX_WIDTH(INDEX_WIDTH),
        .TAG_WIDTH(TAG_WIDTH)
    ) u_tag_array_way0 (
        .clk       (clk),
        .rst_n     (rst_n),
        .index     (current_index),
        .tag_we    (tag_we0),
        .tag_in    (latched_addr[`TAG_MSB:`TAG_LSB]),
        .dirty_we  (dirty_we0),
        .dirty_in  (dirty_in0),
        .tag_out   (tag0),
        .valid_out (valid0),
        .dirty_out (dirty0)
    );

    // Way 1 Tag Array
    tag_array #(
        .NUM_SETS(NUM_SETS),
        .INDEX_WIDTH(INDEX_WIDTH),
        .TAG_WIDTH(TAG_WIDTH)
    ) u_tag_array_way1 (
        .clk       (clk),
        .rst_n     (rst_n),
        .index     (current_index),
        .tag_we    (tag_we1),
        .tag_in    (latched_addr[`TAG_MSB:`TAG_LSB]),
        .dirty_we  (dirty_we1),
        .dirty_in  (dirty_in1),
        .tag_out   (tag1),
        .valid_out (valid1),
        .dirty_out (dirty1)
    );

    // Way 0 Data Array
    data_array #(
        .NUM_SETS(NUM_SETS),
        .INDEX_WIDTH(INDEX_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .WORD_SEL_WIDTH(WORD_SEL_WIDTH)
    ) u_data_array_way0 (
        .clk       (clk),
        .rst_n     (rst_n),
        .index     (current_index),
        .word_idx  (current_word_idx),
        .line_we   (line_we0),
        .line_in   (refill_line),
        .word_we   (word_we0),
        .word_in   (latched_wdata),
        .line_out  (line_out0),
        .word_out  (word_out0)
    );

    // Way 1 Data Array
    data_array #(
        .NUM_SETS(NUM_SETS),
        .INDEX_WIDTH(INDEX_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .WORD_SEL_WIDTH(WORD_SEL_WIDTH)
    ) u_data_array_way1 (
        .clk       (clk),
        .rst_n     (rst_n),
        .index     (current_index),
        .word_idx  (current_word_idx),
        .line_we   (line_we1),
        .line_in   (refill_line),
        .word_we   (word_we1),
        .word_in   (latched_wdata),
        .line_out  (line_out1),
        .word_out  (word_out1)
    );

    // LRU Replacement Logic
    lru_logic #(
        .NUM_SETS(NUM_SETS),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) u_lru_logic (
        .clk            (clk),
        .rst_n          (rst_n),
        .index          (current_index),
        .valid0         (valid0),
        .valid1         (valid1),
        .lru_update     (lru_update),
        .access_way     (lru_access_way),
        .lru_bit        (lru_bit),
        .victim_way     (victim_way)
    );

    // Cache Controller FSM
    cache_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH),
        .WORD_SEL_WIDTH(WORD_SEL_WIDTH)
    ) u_cache_controller (
        .clk                 (clk),
        .rst_n               (rst_n),

        // CPU Interface
        .cpu_req             (cpu_req),
        .cpu_we              (cpu_we),
        .cpu_addr            (cpu_addr),
        .cpu_wdata           (cpu_wdata),
        .cpu_ready           (cpu_ready),

        // Datapath Status
        .hit                 (hit),
        .hit_way             (hit_way),
        .valid0              (valid0),
        .valid1              (valid1),
        .dirty0              (dirty0),
        .dirty1              (dirty1),
        .tag0                (tag0),
        .tag1                (tag1),
        .line_out0           (line_out0),
        .line_out1           (line_out1),
        .victim_way          (victim_way),

        // Main Memory Interface
        .mem_req             (mem_req),
        .mem_we              (mem_we),
        .mem_addr            (mem_addr),
        .mem_wdata           (mem_wdata),
        .mem_rdata           (mem_rdata),
        .mem_ready           (mem_ready),

        // Datapath Controls
        .latched_addr        (latched_addr),
        .latched_wdata       (latched_wdata),
        .latched_we          (latched_we),
        .refill_line         (refill_line),
        .sel_refill_data     (sel_refill_data),

        .tag_we0             (tag_we0),
        .dirty_we0           (dirty_we0),
        .dirty_in0           (dirty_in0),
        .line_we0            (line_we0),
        .word_we0            (word_we0),

        .tag_we1             (tag_we1),
        .dirty_we1           (dirty_we1),
        .dirty_in1           (dirty_in1),
        .line_we1            (line_we1),
        .word_we1            (word_we1),

        .lru_update          (lru_update),
        .lru_access_way      (lru_access_way),

        .fsm_state           (state_out)
    );

endmodule
