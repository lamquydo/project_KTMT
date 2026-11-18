// tag_array.v - Mảng lưu Tag (21-bit), Valid (1-bit) và Dirty (1-bit) cho 1 Way

`timescale 1ns / 1ps
`include "cache_defines.vh"

module tag_array #(
    parameter NUM_SETS    = `NUM_SETS,
    parameter INDEX_WIDTH = `INDEX_WIDTH,
    parameter TAG_WIDTH   = `TAG_WIDTH
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire [INDEX_WIDTH-1:0] index,      // Chọn 1 trong 128 Sets

    input  wire                   tag_we,     // Cho phép ghi Tag mới và bật Valid = 1
    input  wire [TAG_WIDTH-1:0]   tag_in,
    input  wire                   dirty_we,   // Cho phép cập nhật cờ Dirty
    input  wire                   dirty_in,

    output wire [TAG_WIDTH-1:0]   tag_out,
    output wire                   valid_out,
    output wire                   dirty_out
);

    reg [TAG_WIDTH-1:0] tag_mem   [0:NUM_SETS-1];
    reg                 valid_mem [0:NUM_SETS-1];
    reg                 dirty_mem [0:NUM_SETS-1];

    integer i;

    // Ghi đồng bộ theo sườn lên clock
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset toàn bộ Cache về trạng thái rỗng
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                valid_mem[i] <= 1'b0;
                dirty_mem[i] <= 1'b0;
                tag_mem[i]   <= {TAG_WIDTH{1'b0}};
            end
        end else begin
            // Khi nạp dòng mới từ DRAM -> lưu Tag và đánh dấu hợp lệ
            if (tag_we) begin
                tag_mem[index]   <= tag_in;
                valid_mem[index] <= 1'b1;
            end

            if (dirty_we) begin
                dirty_mem[index] <= dirty_in;
            end
        end
    end

    // Đọc tổ hợp để so sánh Tag ngay trong chu kỳ COMPARE_TAG
    assign tag_out   = tag_mem[index];
    assign valid_out = valid_mem[index];
    assign dirty_out = dirty_mem[index];

endmodule
