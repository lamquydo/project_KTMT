// =============================================================================
// File: lru_logic.v
// Description: Synthesizable LRU (Least Recently Used) Replacement Logic
//              Maintains a 1-bit LRU tracker per set for 2-Way Set-Associative Cache.
//              Prioritizes empty (invalid) lines before evicting valid lines.
// Course: Computer Architecture (Kien Truc May Tinh)
// =============================================================================

`timescale 1ns / 1ps
`include "cache_defines.vh"

module lru_logic #(
    parameter NUM_SETS    = `NUM_SETS,
    parameter INDEX_WIDTH = `INDEX_WIDTH
)(
    input  wire                   clk,
    input  wire                   rst_n,
    
    // Set Address
    input  wire [INDEX_WIDTH-1:0] index,
    
    // Status of Lines in the current Set
    input  wire                   valid0,
    input  wire                   valid1,
    
    // Update Interface
    input  wire                   lru_update,   // Asserted on Hit or Successful Refill
    input  wire                   access_way,   // 0: Way 0 accessed, 1: Way 1 accessed
    
    // Replacement Outputs
    output wire                   lru_bit,      // Raw LRU bit: 0 -> Way 0 is LRU, 1 -> Way 1 is LRU
    output reg                    victim_way    // Selected victim way for eviction/allocation
);

    // 1-bit LRU register for each set
    // Value = 0: Way 0 is LRU (Way 1 MRU)
    // Value = 1: Way 1 is LRU (Way 0 MRU)
    reg lru_mem [0:NUM_SETS-1];

    integer i;

    // Synchronous Update / Reset
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                lru_mem[i] <= 1'b0; // Default: Way 0 is initial victim candidate
            end
        end else if (lru_update) begin
            // If Way 0 accessed -> Way 1 becomes LRU (bit <= 1)
            // If Way 1 accessed -> Way 0 becomes LRU (bit <= 0)
            lru_mem[index] <= ~access_way;
        end
    end

    // Combinational Read of LRU bit
    assign lru_bit = lru_mem[index];

    // Combinational Victim Selection
    // 1. If Way 0 is invalid (empty), fill Way 0 first.
    // 2. If Way 1 is invalid (empty), fill Way 1 next.
    // 3. If both ways are valid, select strictly by LRU bit.
    always @(*) begin
        if (!valid0) begin
            victim_way = 1'b0;
        end else if (!valid1) begin
            victim_way = 1'b1;
        end else begin
            victim_way = lru_bit;
        end
    end

endmodule
