// =============================================================================
// File: tag_array.v
// Description: Synthesizable Tag Array for 1 Way of Cache Memory
//              Stores Tag bits, Valid bit, and Dirty bit for NUM_SETS lines.
//              Combinational read allows single-cycle tag comparison.
// Course: Computer Architecture (Kien Truc May Tinh)
// =============================================================================

`timescale 1ns / 1ps
`include "cache_defines.vh"

module tag_array #(
    parameter NUM_SETS    = `NUM_SETS,
    parameter INDEX_WIDTH = `INDEX_WIDTH,
    parameter TAG_WIDTH   = `TAG_WIDTH
)(
    input  wire                   clk,
    input  wire                   rst_n,
    
    // Read / Write Set Index
    input  wire [INDEX_WIDTH-1:0] index,
    
    // Write Control & Data
    input  wire                   tag_we,      // Update tag & set valid <= 1'b1
    input  wire [TAG_WIDTH-1:0]   tag_in,
    input  wire                   dirty_we,    // Update dirty bit
    input  wire                   dirty_in,
    
    // Read Outputs (Asynchronous / Combinational)
    output wire [TAG_WIDTH-1:0]   tag_out,
    output wire                   valid_out,
    output wire                   dirty_out
);

    // Storage arrays
    reg [TAG_WIDTH-1:0] tag_mem   [0:NUM_SETS-1];
    reg                 valid_mem [0:NUM_SETS-1];
    reg                 dirty_mem [0:NUM_SETS-1];

    integer i;

    // Reset and Synchronous Write Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                valid_mem[i] <= 1'b0;
                dirty_mem[i] <= 1'b0;
                tag_mem[i]   <= {TAG_WIDTH{1'b0}};
            end
        end else begin
            // Tag & Valid Update (typically on cache refill/allocation)
            if (tag_we) begin
                tag_mem[index]   <= tag_in;
                valid_mem[index] <= 1'b1;
            end
            
            // Dirty bit update (on write hit or cache refill)
            if (dirty_we) begin
                dirty_mem[index] <= dirty_in;
            end
        end
    end

    // Combinational Read Outputs
    assign tag_out   = tag_mem[index];
    assign valid_out = valid_mem[index];
    assign dirty_out = dirty_mem[index];

endmodule
