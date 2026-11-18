// lru_logic.v - Quản lý thay thế True LRU (1-bit/Set) và chọn Victim Way
// Quy ước bit LRU: 0 -> Way 0 ít dùng nhất | 1 -> Way 1 ít dùng nhất

`timescale 1ns / 1ps
`include "cache_defines.vh"

module lru_logic #(
    parameter NUM_SETS    = `NUM_SETS,
    parameter INDEX_WIDTH = `INDEX_WIDTH
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire [INDEX_WIDTH-1:0] index,

    input  wire                   valid0,
    input  wire                   valid1,

    input  wire                   lru_update,  // Bật = 1 khi Hit hoặc Refill xong
    input  wire                   access_way,  // Way vừa truy cập (0 hoặc 1)

    output wire                   lru_bit,
    output reg                    victim_way   // Way được chọn để nạp/thay thế
);

    reg lru_mem [0:NUM_SETS-1];

    integer i;

    // Cập nhật bit LRU: truy cập Way nào thì Way còn lại thành LRU
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                lru_mem[i] <= 1'b0;
            end
        end 
        else if (lru_update) begin
            if (access_way == 1'b0) begin
                lru_mem[index] <= 1'b1;
            end 
            else begin
                lru_mem[index] <= 1'b0;
            end
        end
    end

    assign lru_bit = lru_mem[index];

    // Chọn Victim Way: ưu tiên Way còn trống trước, đầy cả 2 Way mới xét lru_bit
    always @(*) begin
        if (valid0 == 1'b0) begin
            victim_way = 1'b0;
        end 
        else if (valid1 == 1'b0) begin
            victim_way = 1'b1;
        end 
        else begin
            victim_way = lru_bit;
        end
    end

endmodule
