// =============================================================================
// Tên file   : cache_defines.vh
// Mô tả      : File Header định nghĩa các tham số kiến trúc & mã hóa trạng thái FSM
// Đề tài     : Thiết kế bộ nhớ đệm 4KB 2-Way Set-Associative Cache Controller
// Giáo trình : Kiến trúc máy tính (Patterson & Hennessy - Chương 5)
// =============================================================================

// Kiểm tra xem file đã được nạp vào bộ nhớ chưa, nếu chưa thì nạp vào
`ifndef CACHE_DEFINES_VH
`define CACHE_DEFINES_VH

// -----------------------------------------------------------------------------
// 1. CÁC THAM SỐ DUNG LƯỢNG VÀ KÍCH THƯỚC KIẾN TRÚC
// -----------------------------------------------------------------------------
`define ADDR_WIDTH          32       // Độ rộng địa chỉ Byte của CPU: 32-bit
`define DATA_WIDTH          32       // Độ rộng một từ (Word) của CPU: 32-bit (4 Bytes)
`define LINE_BYTES          16       // Kích thước 1 dòng Cache: 16 Bytes
`define LINE_WIDTH          128      // 16 Bytes * 8 bits = 128 bits (chứa 4 Words)
`define WORDS_PER_LINE      4        // Mỗi dòng chứa 4 từ: 128 / 32 = 4 Words
`define NUM_WAYS            2        // Độ kết hợp: 2-Way (mỗi Set gồm Way 0 và Way 1)
`define NUM_SETS            128      // Tổng số Set: (4096 Bytes / 16 Bytes) / 2 Ways = 128 Sets

// -----------------------------------------------------------------------------
// 2. PHÂN HOẠCH CÁC TRƯỜNG BIT TRONG ĐỊA CHỈ 32-BIT: cpu_addr[31:0]
// 
//  31                         11 10           4 3        2 1        0
// +-----------------------------+--------------+----------+----------+
// |          Tag (21 bits)      | Index (7 bit)| Word(2b) | Byte(2b) |
// +-----------------------------+--------------+----------+----------+
// -----------------------------------------------------------------------------

// [1:0] Byte Offset (2 bits): Chọn 1 trong 4 bytes trong một Word 32-bit
`define BYTE_OFFSET_MSB     1
`define BYTE_OFFSET_LSB     0
`define BYTE_OFFSET_WIDTH   2

// [3:2] Word Select (2 bits): Chọn 1 trong 4 Words trong dòng 128-bit
`define WORD_SEL_MSB        3
`define WORD_SEL_LSB        2
`define WORD_SEL_WIDTH      2

// [3:0] Block Offset (4 bits = Word Select + Byte Offset): Định vị byte trong dòng 16 Bytes
`define BLOCK_OFFSET_MSB    3
`define BLOCK_OFFSET_LSB    0
`define BLOCK_OFFSET_WIDTH  4

// [10:4] Set Index (7 bits): Giải mã chọn 1 trong 128 Sets (2^7 = 128)
`define INDEX_MSB           10
`define INDEX_LSB           4
`define INDEX_WIDTH         7

// [31:11] Tag (21 bits): Nhận diện khối nhớ vật lý trong DRAM (32 - 7 - 4 = 21 bits)
`define TAG_MSB             31
`define TAG_LSB             11
`define TAG_WIDTH           21

// -----------------------------------------------------------------------------
// 3. MÃ HÓA CÁC TRẠNG THÁI CỦA MÁY TRẠNG THÁI HỮU HẠN FSM (3-bit)
// Bám sát lưu đồ điều khiển Cache trong giáo trình Patterson & Hennessy
// -----------------------------------------------------------------------------
`define STATE_IDLE          3'b000   // Trạng thái nghỉ: Chờ CPU gửi yêu cầu đọc/ghi
`define STATE_COMPARE_TAG   3'b001   // So sánh Tag: Kiểm tra Hit/Miss trong 1 chu kỳ
`define STATE_WRITE_BACK    3'b010   // Ghi trả: Đẩy dòng nạn nhân bẩn (Dirty) về DRAM
`define STATE_FETCH_MEM     3'b011   // Nạp dữ liệu: Đọc dòng 128-bit mới từ DRAM
`define STATE_REFILL_UPDATE 3'b100   // Cập nhật: Nạp dòng vào Cache và trả dữ liệu cho CPU

`endif // CACHE_DEFINES_VH
