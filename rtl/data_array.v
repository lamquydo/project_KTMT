// data_array.v - Mảng lưu dữ liệu cho 1 Way (128 dòng x 128-bit = 2 KB)

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

    input  wire [INDEX_WIDTH-1:0]    index,
    input  wire [WORD_SEL_WIDTH-1:0] word_idx,

    // Ghi cả dòng 128-bit (dùng khi Refill từ DRAM)
    input  wire                      line_we,
    input  wire [LINE_WIDTH-1:0]     line_in,

    // Ghi 1 từ 32-bit (dùng khi Write Hit)
    input  wire                      word_we,
    input  wire [DATA_WIDTH-1:0]     word_in,

    output wire [LINE_WIDTH-1:0]     line_out,    // Xuất cả dòng khi Write-Back
    output wire [DATA_WIDTH-1:0]     word_out     // Xuất 1 Word trả về CPU
);

    reg [LINE_WIDTH-1:0] data_mem [0:NUM_SETS-1];

    integer i;

    // Ghi đồng bộ theo sườn lên clock
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                data_mem[i] <= {LINE_WIDTH{1'b0}};
            end
        end else begin
            if (line_we) begin
                data_mem[index] <= line_in;
            end
            // Chỉ ghi đè đúng Word 32-bit được chọn, giữ nguyên 3 Word còn lại
            else if (word_we) begin
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

    // Đọc tổ hợp: xuất cả dòng 128-bit và chọn Word 32-bit qua MUX 4-1
    assign line_out = data_mem[index];

    assign word_out = (word_idx == 2'b00) ? line_out[31:0]   :
                      (word_idx == 2'b01) ? line_out[63:32]  :
                      (word_idx == 2'b10) ? line_out[95:64]  :
                                            line_out[127:96];

endmodule
