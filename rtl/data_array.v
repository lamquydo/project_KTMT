// =============================================================================
// File: data_array.v
// Description: Synthesizable Data Array for 1 Way of Cache Memory
//              Stores NUM_SETS lines, each 128-bit wide (4 words x 32 bits).
//              Supports full-line write (refill) and individual word write (write hit).
// Course: Computer Architecture (Kien Truc May Tinh)
// =============================================================================

`timescale 1ns / 1ps
`include "cache_defines.vh"

module data_array #(
    parameter NUM_SETS        = `NUM_SETS,
    parameter INDEX_WIDTH     = `INDEX_WIDTH,
    parameter LINE_WIDTH      = `LINE_WIDTH,
    parameter DATA_WIDTH      = `DATA_WIDTH,
    parameter WORD_SEL_WIDTH  = `WORD_SEL_WIDTH
)(
    input  wire                      clk,
    input  wire                      rst_n,
    
    // Set and Word Addressing
    input  wire [INDEX_WIDTH-1:0]    index,
    input  wire [WORD_SEL_WIDTH-1:0] word_idx,
    
    // Write Enables & Data Inputs
    input  wire                      line_we,    // Full 128-bit line write (refill)
    input  wire [LINE_WIDTH-1:0]     line_in,
    input  wire                      word_we,    // Single 32-bit word write (write hit)
    input  wire [DATA_WIDTH-1:0]     word_in,
    
    // Read Outputs
    output wire [LINE_WIDTH-1:0]     line_out,   // Entire line (for DRAM write-back)
    output wire [DATA_WIDTH-1:0]     word_out    // Selected word (for CPU read)
);

    // 128 sets of 128-bit cache lines
    reg [LINE_WIDTH-1:0] data_mem [0:NUM_SETS-1];

    integer i;

    // Synchronous Write Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                data_mem[i] <= {LINE_WIDTH{1'b0}};
            end
        end else begin
            if (line_we) begin
                // Update entire 128-bit line from memory refill
                data_mem[index] <= line_in;
            end else if (word_we) begin
                // Partial update: modify only the requested 32-bit word
                case (word_idx)
                    2'b00: data_mem[index][31:0]   <= word_in;
                    2'b01: data_mem[index][63:32]  <= word_in;
                    2'b10: data_mem[index][95:64]  <= word_in;
                    2'b11: data_mem[index][127:96] <= word_in;
                    default: ;
                endcase
            end
        end
    end

    // Combinational Read Logic
    assign line_out = data_mem[index];

    // Word selection multiplexer for CPU data bus
    assign word_out = (word_idx == 2'b00) ? line_out[31:0]   :
                      (word_idx == 2'b01) ? line_out[63:32]  :
                      (word_idx == 2'b10) ? line_out[95:64]  :
                                            line_out[127:96];

endmodule
