// =============================================================================
// File: main_memory_model.v
// Description: Behavioral Simulation Model of Main Memory (DRAM)
//              Features:
//                - Configurable read/write latency (e.g. 6 clock cycles).
//                - 128-bit wide burst/line access (16 bytes per line).
//                - Memory initialized with deterministic test patterns.
// Course: Computer Architecture (Kien Truc May Tinh)
// =============================================================================

`timescale 1ns / 1ps
`include "../rtl/cache_defines.vh"

module main_memory_model #(
    parameter LATENCY_CYCLES = 6,
    parameter MEM_LINES      = 16384 // 16K lines x 16 bytes = 256KB simulated space
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Memory Bus Interface
    input  wire                   mem_req,
    input  wire                   mem_we,
    input  wire [`ADDR_WIDTH-1:0] mem_addr,   // Byte address (16-byte block aligned)
    input  wire [`LINE_WIDTH-1:0] mem_wdata,  // 128-bit line write
    output reg  [`LINE_WIDTH-1:0] mem_rdata,  // 128-bit line read
    output reg                    mem_ready
);

    // 16K lines of 128-bit DRAM storage
    reg [`LINE_WIDTH-1:0] mem_storage [0:MEM_LINES-1];

    reg [3:0]              latency_counter;
    reg                    busy;
    reg                    latched_we;
    reg [13:0]             latched_line_idx;
    reg [`LINE_WIDTH-1:0]  latched_wdata;

    // Line index derived from address bits [17:4]
    wire [13:0] line_idx = mem_addr[17:4];

    integer i;
    reg [31:0] init_w0, init_w1, init_w2, init_w3;
    initial begin
        // Initialize DRAM contents with distinct recognizable pattern:
        // Word 0 = Addr + 0, Word 1 = Addr + 4, Word 2 = Addr + 8, Word 3 = Addr + 12
        for (i = 0; i < MEM_LINES; i = i + 1) begin
            init_w0 = 32'h1000_0000 | (i * 16 + 0);
            init_w1 = 32'h1000_0000 | (i * 16 + 4);
            init_w2 = 32'h1000_0000 | (i * 16 + 8);
            init_w3 = 32'h1000_0000 | (i * 16 + 12);
            mem_storage[i] = {init_w3, init_w2, init_w1, init_w0};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latency_counter  <= 4'd0;
            busy             <= 1'b0;
            latched_we       <= 1'b0;
            latched_line_idx <= 14'd0;
            latched_wdata    <= {`LINE_WIDTH{1'b0}};
            mem_ready        <= 1'b0;
            mem_rdata        <= {`LINE_WIDTH{1'b0}};
        end else begin
            mem_ready <= 1'b0; // Default: 1-cycle strobe

            if (!busy) begin
                if (mem_req && !mem_ready) begin
                    busy             <= 1'b1;
                    latency_counter  <= 4'd1;
                    latched_we       <= mem_we;
                    latched_line_idx <= line_idx;
                    latched_wdata    <= mem_wdata;
                end
            end else begin
                if (latency_counter < LATENCY_CYCLES) begin
                    latency_counter <= latency_counter + 1'b1;
                end else begin
                    // Latency completed: fulfill read or write operation
                    busy            <= 1'b0;
                    mem_ready       <= 1'b1;
                    latency_counter <= 4'd0;

                    if (latched_we) begin
                        // DRAM Write operation
                        mem_storage[latched_line_idx] <= latched_wdata;
                    end else begin
                        // DRAM Read operation
                        mem_rdata <= mem_storage[latched_line_idx];
                    end
                end
            end
        end
    end

endmodule
