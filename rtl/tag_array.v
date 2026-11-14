// =============================================================================
// Tên file   : tag_array.v
// Chức năng  : Mảng lưu trữ Thẻ địa chỉ (Tag Array) cho 1 Way của Cache
//              Lưu trữ: Tag (21 bit), Valid (1 bit), và Dirty (1 bit) cho 128 Sets
// Giáo trình : Kiến trúc máy tính (Patterson & Hennessy - Chương 5)
// =============================================================================

`timescale 1ns / 1ps
`include "cache_defines.vh"

module tag_array #(
    parameter NUM_SETS    = `NUM_SETS,    // Số lượng Set: 128
    parameter INDEX_WIDTH = `INDEX_WIDTH,  // Độ rộng bit Index: 7 bits
    parameter TAG_WIDTH   = `TAG_WIDTH    // Độ rộng bit Tag: 21 bits
)(
    // Tín hiệu đồng bộ hệ thống
    input  wire                   clk,        // Xung nhịp hệ thống (Clock 100MHz)
    input  wire                   rst_n,      // Tín hiệu Reset tích cực mức thấp (Active-low)

    // Chỉ số hàng (Set Index) được truy cập (từ 0 đến 127)
    input  wire [INDEX_WIDTH-1:0] index,

    // Tín hiệu điều khiển ghi từ Cache Controller
    input  wire                   tag_we,     // Cho phép cập nhật Tag mới và bật Valid = 1 (khi Refill)
    input  wire [TAG_WIDTH-1:0]   tag_in,     // Giá trị Tag 21-bit cần nạp vào
    input  wire                   dirty_we,   // Cho phép cập nhật cờ Dirty
    input  wire                   dirty_in,   // Giá trị cờ Dirty mới (1: bẩn, 0: sạch)

    // Đầu ra đọc dữ liệu (Mạch tổ hợp - phản hồi tức thì không qua clock)
    output wire [TAG_WIDTH-1:0]   tag_out,    // Tag hiện tại của Set đang xét
    output wire                   valid_out,  // 1: Dữ liệu trong dòng là hợp lệ, 0: rác (sau Reset)
    output wire                   dirty_out   // 1: Dòng đã bị CPU sửa đổi nhưng chưa ghi về DRAM
);

    // -------------------------------------------------------------------------
    // CÁC MẢNG THANH GHI LƯU TRỮ TRONG 1 WAY (128 phần tử mỗi mảng)
    // -------------------------------------------------------------------------
    reg [TAG_WIDTH-1:0] tag_mem   [0:NUM_SETS-1]; // Lưu 128 giá trị Tag 21-bit
    reg                 valid_mem [0:NUM_SETS-1]; // Lưu 128 bit Valid (1 bit / Set)
    reg                 dirty_mem [0:NUM_SETS-1]; // Lưu 128 bit Dirty (1 bit / Set)

    integer i;

    // -------------------------------------------------------------------------
    // 1. MẠCH GHI ĐỒNG BỘ THEO XUNG NHỊP (Synchronous Write)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Khi Reset phần cứng: Xóa toàn bộ cờ Valid và Dirty về 0 (Cold Cache)
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                valid_mem[i] <= 1'b0;
                dirty_mem[i] <= 1'b0;
                tag_mem[i]   <= {TAG_WIDTH{1'b0}};
            end
        end else begin
            // Khi nạp dòng mới từ DRAM (Cache Refill):
            // Cập nhật Tag mới và tự động đánh dấu dòng là hợp lệ (Valid <= 1)
            if (tag_we) begin
                tag_mem[index]   <= tag_in;
                valid_mem[index] <= 1'b1;
            end

            // Khi CPU ghi trúng (Write Hit) hoặc khi vừa nạp xong:
            // Cập nhật cờ Dirty theo tín hiệu dirty_in từ Controller
            if (dirty_we) begin
                dirty_mem[index] <= dirty_in;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. MẠCH ĐỌC TỔ HỢP BẤT ĐỒNG BỘ (Combinational Read)
    // Xuất dữ liệu ngay lập tức theo địa chỉ index để bộ so sánh Tag có thể
    // kiểm tra Hit/Miss ngay trong 1 chu kỳ tại trạng thái COMPARE_TAG.
    // -------------------------------------------------------------------------
    assign tag_out   = tag_mem[index];
    assign valid_out = valid_mem[index];
    assign dirty_out = dirty_mem[index];

endmodule
