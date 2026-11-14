// =============================================================================
// Tên file   : data_array.v
// Chức năng  : Mảng lưu trữ Dữ liệu (Data Array) cho 1 Way của Cache
//              Dung lượng 1 Way: 128 dòng x 16 Bytes = 2,048 Bytes (2 KB)
//              Hỗ trợ: Ghi toàn dòng 128-bit (khi Miss) và ghi 1 từ 32-bit (khi Hit)
// Giáo trình : Kiến trúc máy tính (Patterson & Hennessy - Chương 5)
// =============================================================================

`timescale 1ns / 1ps
`include "cache_defines.vh"

module data_array #(
    parameter NUM_SETS        = `NUM_SETS,        // Số Set: 128
    parameter INDEX_WIDTH     = `INDEX_WIDTH,     // Độ rộng bit Index: 7 bits
    parameter LINE_WIDTH      = `LINE_WIDTH,      // Độ rộng dòng: 128 bits (16 Bytes)
    parameter DATA_WIDTH      = `DATA_WIDTH,      // Độ rộng từ CPU: 32 bits (4 Bytes)
    parameter WORD_SEL_WIDTH  = `WORD_SEL_WIDTH   // Độ rộng chọn từ: 2 bits
)(
    // Tín hiệu đồng bộ hệ thống
    input  wire                      clk,         // Xung nhịp hệ thống (Clock 100MHz)
    input  wire                      rst_n,       // Reset tích cực mức thấp (Active-low)

    // Địa chỉ Set Index và vị trí Word trong dòng
    input  wire [INDEX_WIDTH-1:0]    index,       // bus [6:0]: chọn dòng từ 0 đến 127
    input  wire [WORD_SEL_WIDTH-1:0] word_idx,    // bus [1:0]: chọn 1 trong 4 Words (0..3)

    // Chế độ 1: Ghi toàn bộ dòng 128-bit (dùng khi nạp khối từ DRAM)
    input  wire                      line_we,     // Tín hiệu cho phép ghi cả dòng 128-bit
    input  wire [LINE_WIDTH-1:0]     line_in,     // Dữ liệu dòng 128-bit nạp từ DRAM

    // Chế độ 2: Ghi chọn lọc từng từ 32-bit (dùng khi CPU Write Hit)
    input  wire                      word_we,     // Tín hiệu cho phép ghi 1 từ 32-bit
    input  wire [DATA_WIDTH-1:0]     word_in,     // Dữ liệu từ 32-bit do CPU gửi xuống

    // Đầu ra đọc dữ liệu (Mạch tổ hợp phản hồi tức thì)
    output wire [LINE_WIDTH-1:0]     line_out,    // Toàn bộ dòng 128-bit (đẩy về DRAM khi Write-Back)
    output wire [DATA_WIDTH-1:0]     word_out     // Từ 32-bit được chọn (trả về cho CPU đọc)
);

    // -------------------------------------------------------------------------
    // MẢNG LƯU TRỮ DỮ LIỆU: 128 dòng, mỗi dòng rộng 128 bits
    // Tổng dung lượng phần cứng: 128 x 128 = 16,384 bits = 2 KB
    // -------------------------------------------------------------------------
    reg [LINE_WIDTH-1:0] data_mem [0:NUM_SETS-1];

    integer i;

    // -------------------------------------------------------------------------
    // 1. MẠCH GHI ĐỒNG BỘ THEO SƯỜN LÊN XUNG NHỊP (Synchronous Write)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Khi Reset: Xóa sạch toàn bộ mảng dữ liệu về 0
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                data_mem[i] <= {LINE_WIDTH{1'b0}}; // Tạo chuỗi 128 bit 0
            end
        end else begin
            // Trường hợp A: Nạp dòng mới từ DRAM lên Cache (Cache Refill)
            if (line_we) begin
                data_mem[index] <= line_in;
            end
            // Trường hợp B: CPU ghi trúng (Write Hit) vào 1 từ 32-bit
            // Kỹ thuật cắt lát bit (Bit Slicing): Chỉ cập nhật đúng 32 bit được chọn,
            // giữ nguyên vẹn 96 bit còn lại của dòng nhớ!
            else if (word_we) begin
                case (word_idx)
                    2'b00: data_mem[index][31:0]   <= word_in; // Ghi vào Word 0
                    2'b01: data_mem[index][63:32]  <= word_in; // Ghi vào Word 1
                    2'b10: data_mem[index][95:64]  <= word_in; // Ghi vào Word 2
                    2'b11: data_mem[index][127:96] <= word_in; // Ghi vào Word 3
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. MẠCH ĐỌC TỔ HỢP BẤT ĐỒNG BỘ (Combinational Read)
    // -------------------------------------------------------------------------

    // A. Xuất toàn bộ dòng 128-bit của Set đang xét (dùng khi Write-Back về DRAM)
    assign line_out = data_mem[index];

    // B. Bộ dồn kênh MUX 4-sang-1: Chọn đúng từ 32-bit theo word_idx để trả về cho CPU
    assign word_out = (word_idx == 2'b00) ? line_out[31:0]   :
                      (word_idx == 2'b01) ? line_out[63:32]  :
                      (word_idx == 2'b10) ? line_out[95:64]  :
                                            line_out[127:96];

endmodule
