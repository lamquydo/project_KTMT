// =============================================================================
// File: cache_controller.v
// Description: Synthesizable FSM Controller for 2-Way Set-Associative Cache
//              Policy: Write-Back, Write-Allocate, LRU Replacement.
// States:
//   - STATE_IDLE:          Await CPU request
//   - STATE_COMPARE_TAG:   Check Tag for Hit/Miss; handle Hit or prepare Miss
//   - STATE_WRITE_BACK:    Write dirty victim line to Main Memory
//   - STATE_FETCH_MEM:     Fetch missed line from Main Memory
//   - STATE_REFILL_UPDATE: Write fetched line into Cache & complete CPU request
// Course: Computer Architecture (Kien Truc May Tinh)
// =============================================================================

`timescale 1ns / 1ps
`include "cache_defines.vh"

module cache_controller #(
    parameter ADDR_WIDTH      = `ADDR_WIDTH,
    parameter DATA_WIDTH      = `DATA_WIDTH,
    parameter LINE_WIDTH      = `LINE_WIDTH,
    parameter TAG_WIDTH       = `TAG_WIDTH,
    parameter INDEX_WIDTH     = `INDEX_WIDTH,
    parameter WORD_SEL_WIDTH  = `WORD_SEL_WIDTH
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // CPU Bus Interface
    input  wire                      cpu_req,
    input  wire                      cpu_we,
    input  wire [ADDR_WIDTH-1:0]     cpu_addr,
    input  wire [DATA_WIDTH-1:0]     cpu_wdata,
    output reg                       cpu_ready,

    // Status inputs from Cache Datapath
    input  wire                      hit,
    input  wire                      hit_way,
    input  wire                      valid0,
    input  wire                      valid1,
    input  wire                      dirty0,
    input  wire                      dirty1,
    input  wire [TAG_WIDTH-1:0]      tag0,
    input  wire [TAG_WIDTH-1:0]      tag1,
    input  wire [LINE_WIDTH-1:0]     line_out0,
    input  wire [LINE_WIDTH-1:0]     line_out1,
    input  wire                      victim_way,

    // Main Memory Interface
    output reg                       mem_req,
    output reg                       mem_we,
    output reg  [ADDR_WIDTH-1:0]     mem_addr,
    output reg  [LINE_WIDTH-1:0]     mem_wdata,
    input  wire [LINE_WIDTH-1:0]     mem_rdata,
    input  wire                      mem_ready,

    // Control Signals to Cache Datapath
    output reg  [ADDR_WIDTH-1:0]     latched_addr,
    output reg  [DATA_WIDTH-1:0]     latched_wdata,
    output reg                       latched_we,
    output reg  [LINE_WIDTH-1:0]     refill_line,
    output reg                       sel_refill_data, // 0: cpu_rdata from cache, 1: from refill buffer

    output reg                       tag_we0,
    output reg                       dirty_we0,
    output reg                       dirty_in0,
    output reg                       line_we0,
    output reg                       word_we0,

    output reg                       tag_we1,
    output reg                       dirty_we1,
    output reg                       dirty_in1,
    output reg                       line_we1,
    output reg                       word_we1,

    output reg                       lru_update,
    output reg                       lru_access_way,

    output wire [2:0]                fsm_state
);

    // State registers
    reg [2:0] state, next_state;
    assign fsm_state = state;

    // Registers to latch request attributes and victim details
    reg                  latched_victim_way;
    reg [TAG_WIDTH-1:0]  latched_victim_tag;
    reg [LINE_WIDTH-1:0] latched_victim_data;
    reg [LINE_WIDTH-1:0] latched_mem_rdata;

    // Determine if the selected victim line is dirty and must be written back
    wire victim_dirty = (victim_way == 1'b0) ? (valid0 && dirty0) : (valid1 && dirty1);

    // Synchronous FSM State Transition & Input Latching
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= `STATE_IDLE;
            latched_addr        <= {ADDR_WIDTH{1'b0}};
            latched_wdata       <= {DATA_WIDTH{1'b0}};
            latched_we          <= 1'b0;
            latched_victim_way  <= 1'b0;
            latched_victim_tag  <= {TAG_WIDTH{1'b0}};
            latched_victim_data <= {LINE_WIDTH{1'b0}};
            latched_mem_rdata   <= {LINE_WIDTH{1'b0}};
        end else begin
            state <= next_state;

            // Latch CPU request when in IDLE
            if (state == `STATE_IDLE && cpu_req) begin
                latched_addr  <= cpu_addr;
                latched_wdata <= cpu_wdata;
                latched_we    <= cpu_we;
            end

            // Latch victim details if a miss is confirmed during COMPARE_TAG
            if (state == `STATE_COMPARE_TAG && !hit) begin
                latched_victim_way  <= victim_way;
                latched_victim_tag  <= (victim_way == 1'b0) ? tag0 : tag1;
                latched_victim_data <= (victim_way == 1'b0) ? line_out0 : line_out1;
            end

            // Latch DRAM data when read is completed
            if (state == `STATE_FETCH_MEM && mem_ready) begin
                latched_mem_rdata <= mem_rdata;
            end
        end
    end

    // Combinational Next-State Logic
    always @(*) begin
        next_state = state;
        case (state)
            `STATE_IDLE: begin
                if (cpu_req) begin
                    next_state = `STATE_COMPARE_TAG;
                end
            end

            `STATE_COMPARE_TAG: begin
                if (hit) begin
                    // Read or Write Hit completes in 1 cycle
                    next_state = `STATE_IDLE;
                end else begin
                    // Miss handling: check if victim line needs write-back
                    if (victim_dirty) begin
                        next_state = `STATE_WRITE_BACK;
                    end else begin
                        next_state = `STATE_FETCH_MEM;
                    end
                end
            end

            `STATE_WRITE_BACK: begin
                if (mem_ready) begin
                    next_state = `STATE_FETCH_MEM;
                end
            end

            `STATE_FETCH_MEM: begin
                if (mem_ready) begin
                    next_state = `STATE_REFILL_UPDATE;
                end
            end

            `STATE_REFILL_UPDATE: begin
                next_state = `STATE_IDLE;
            end

            default: next_state = `STATE_IDLE;
        endcase
    end

    // Word substitution for Write-Allocate merge
    reg [LINE_WIDTH-1:0] merged_line;
    always @(*) begin
        merged_line = latched_mem_rdata;
        case (latched_addr[`WORD_SEL_MSB:`WORD_SEL_LSB])
            2'b00: merged_line[31:0]   = latched_wdata;
            2'b01: merged_line[63:32]  = latched_wdata;
            2'b10: merged_line[95:64]  = latched_wdata;
            2'b11: merged_line[127:96] = latched_wdata;
            default: ;
        endcase
    end

    // Combinational Output Control Logic
    always @(*) begin
        // Default values to prevent latches
        cpu_ready       = 1'b0;
        sel_refill_data = 1'b0;
        mem_req         = 1'b0;
        mem_we          = 1'b0;
        mem_addr        = {ADDR_WIDTH{1'b0}};
        mem_wdata       = {LINE_WIDTH{1'b0}};
        refill_line     = latched_mem_rdata;

        tag_we0         = 1'b0;
        dirty_we0       = 1'b0;
        dirty_in0       = 1'b0;
        line_we0        = 1'b0;
        word_we0        = 1'b0;

        tag_we1         = 1'b0;
        dirty_we1       = 1'b0;
        dirty_in1       = 1'b0;
        line_we1        = 1'b0;
        word_we1        = 1'b0;

        lru_update      = 1'b0;
        lru_access_way  = 1'b0;

        case (state)
            `STATE_IDLE: begin
                // All control signals idle
            end

            `STATE_COMPARE_TAG: begin
                if (hit) begin
                    cpu_ready      = 1'b1;
                    lru_update     = 1'b1;
                    lru_access_way = hit_way;

                    if (latched_we) begin
                        // Write Hit: update word and mark line dirty
                        if (hit_way == 1'b0) begin
                            word_we0  = 1'b1;
                            dirty_we0 = 1'b1;
                            dirty_in0 = 1'b1;
                        end else begin
                            word_we1  = 1'b1;
                            dirty_we1 = 1'b1;
                            dirty_in1 = 1'b1;
                        end
                    end
                end
            end

            `STATE_WRITE_BACK: begin
                mem_req   = ~mem_ready;
                mem_we    = 1'b1;
                mem_addr  = {latched_victim_tag, latched_addr[`INDEX_MSB:`INDEX_LSB], 4'b0000};
                mem_wdata = latched_victim_data;
            end

            `STATE_FETCH_MEM: begin
                mem_req   = ~mem_ready;
                mem_we    = 1'b0;
                mem_addr  = {latched_addr[ADDR_WIDTH-1:`BLOCK_OFFSET_WIDTH], 4'b0000};
            end

            `STATE_REFILL_UPDATE: begin
                cpu_ready       = 1'b1;
                sel_refill_data = 1'b1;
                lru_update      = 1'b1;
                lru_access_way  = latched_victim_way;

                if (!latched_we) begin
                    // Read Miss refill
                    refill_line = latched_mem_rdata;
                    if (latched_victim_way == 1'b0) begin
                        tag_we0   = 1'b1;
                        dirty_we0 = 1'b1;
                        dirty_in0 = 1'b0; // Clean
                        line_we0  = 1'b1;
                    end else begin
                        tag_we1   = 1'b1;
                        dirty_we1 = 1'b1;
                        dirty_in1 = 1'b0; // Clean
                        line_we1  = 1'b1;
                    end
                end else begin
                    // Write Miss refill (Write-Allocate): write merged data & set dirty
                    refill_line = merged_line;
                    if (latched_victim_way == 1'b0) begin
                        tag_we0   = 1'b1;
                        dirty_we0 = 1'b1;
                        dirty_in0 = 1'b1; // Dirty
                        line_we0  = 1'b1;
                    end else begin
                        tag_we1   = 1'b1;
                        dirty_we1 = 1'b1;
                        dirty_in1 = 1'b1; // Dirty
                        line_we1  = 1'b1;
                    end
                end
            end

            default: ;
        endcase
    end

endmodule
