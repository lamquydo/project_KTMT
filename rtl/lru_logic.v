// =============================================================================
// Tên file : lru_logic.v
// Chức năng: Khối phần cứng quản lý thuật toán thay thế True LRU
//            (Least Recently Used) cho bộ nhớ đệm 2-Way Set-Associative Cache.
//
// Quy ước bit LRU cho mỗi Set:
//   - Giá trị = 0 : Way 0 là đường ít được dùng nhất (nạn nhân cần đuổi là Way 0)
//   - Giá trị = 1 : Way 1 là đường ít được dùng nhất (nạn nhân cần đuổi là Way 1)
// =============================================================================

`timescale 1ns / 1ps
`include "cache_defines.vh"

module lru_logic #(
    parameter NUM_SETS    = `NUM_SETS,    // Số lượng Set: 128 Sets
    parameter INDEX_WIDTH = `INDEX_WIDTH  // Độ rộng bit Index: 7 bits
)(
    // Tín hiệu xung nhịp và reset
    input  wire                   clk,
    input  wire                   rst_n,

    // Địa chỉ chỉ số Set đang được CPU truy cập (0 đến 127)
    input  wire [INDEX_WIDTH-1:0] index,

    // Cờ báo dữ liệu hợp lệ (Valid) của 2 Way tại Set hiện tại
    input  wire                   valid0,      // 1: Way 0 đã có dữ liệu hợp lệ, 0: còn trống
    input  wire                   valid1,      // 1: Way 1 đã có dữ liệu hợp lệ, 0: còn trống

    // Tín hiệu điều khiển cập nhật từ Cache Controller
    input  wire                   lru_update,  // Kích hoạt = 1 khi có Hit hoặc vừa nạp xong dòng mới
    input  wire                   access_way,  // Đường vừa được truy cập: 0 là Way 0, 1 là Way 1

    // Ngõ ra điều khiển
    output wire                   lru_bit,     // Giá trị bit LRU thô của Set hiện tại
    output reg                    victim_way   // Đường nạn nhân được chọn để nạp hoặc đuổi (0 hoặc 1)
);

    // -------------------------------------------------------------------------
    // BỘ NHỚ LƯU TRỮ TRẠNG THÁI LRU
    // Mảng 128 thanh ghi 1-bit, mỗi bit đại diện cho 1 Set
    // -------------------------------------------------------------------------
    reg lru_mem [0:NUM_SETS-1];

    integer i;


    // -------------------------------------------------------------------------
    // KHỐI 1: CẬP NHẬT TRẠNG THÁI LRU (Mạch tuần tự theo sườn lên xung nhịp clk)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Khi Reset phần cứng: Xóa toàn bộ mảng về 0 (Mặc định chọn Way 0 trước)
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                lru_mem[i] <= 1'b0;
            end
        end 
        else if (lru_update) begin
            // Khi có yêu cầu cập nhật, xét đường vừa được truy cập:
            if (access_way == 1'b0) begin
                // Nếu vừa truy cập Way 0:
                // -> Way 1 trở thành đường ít dùng gần đây nhất (LRU = 1)
                lru_mem[index] <= 1'b1;
            end 
            else begin
                // Nếu vừa truy cập Way 1:
                // -> Way 0 trở thành đường ít dùng gần đây nhất (LRU = 0)
                lru_mem[index] <= 1'b0;
            end
        end
    end


    // -------------------------------------------------------------------------
    // KHỐI 2: ĐỌC GIÁ TRỊ BIT LRU (Mạch tổ hợp - Phản hồi tức thì)
    // -------------------------------------------------------------------------
    assign lru_bit = lru_mem[index];


    // -------------------------------------------------------------------------
    // KHỐI 3: MẠCH CHỌN ĐƯỜNG NẠN NHÂN (Victim Selection - Mạch tổ hợp)
    // Nguyên tắc:
    //   1. Ưu tiên cấp phát vào Way đang trống (Valid = 0) trước.
    //   2. Khi cả 2 Way đều đã đầy (Valid = 1), mới quyết định đuổi theo bit LRU.
    // -------------------------------------------------------------------------
    always @(*) begin
        if (valid0 == 1'b0) begin
            // Trường hợp 1: Way 0 đang trống -> Chọn Way 0 để nạp dữ liệu
            victim_way = 1'b0;
        end 
        else if (valid1 == 1'b0) begin
            // Trường hợp 2: Way 0 đã đầy nhưng Way 1 còn trống -> Chọn Way 1 để nạp dữ liệu
            victim_way = 1'b1;
        end 
        else begin
            // Trường hợp 3: Cả hai Way đều đã có dữ liệu hợp lệ -> Đuổi đường ít dùng nhất
            victim_way = lru_bit;
        end
    end

endmodule
