// cache_defines.vh - Định nghĩa tham số kiến trúc Cache và các trạng thái FSM

`ifndef CACHE_DEFINES_VH
`define CACHE_DEFINES_VH

// Tham số kiến trúc: 4KB, 2-Way Set-Associative, 16B/Line (4 Words)
`define ADDR_WIDTH          32
`define DATA_WIDTH          32
`define LINE_BYTES          16
`define LINE_WIDTH          128
`define WORDS_PER_LINE      4
`define NUM_WAYS            2
`define NUM_SETS            128

// Phân chia địa chỉ 32-bit: [31:11] Tag | [10:4] Index | [3:2] Word | [1:0] Byte
`define BYTE_OFFSET_MSB     1
`define BYTE_OFFSET_LSB     0
`define BYTE_OFFSET_WIDTH   2

`define WORD_SEL_MSB        3
`define WORD_SEL_LSB        2
`define WORD_SEL_WIDTH      2

`define BLOCK_OFFSET_MSB    3
`define BLOCK_OFFSET_LSB    0
`define BLOCK_OFFSET_WIDTH  4

`define INDEX_MSB           10
`define INDEX_LSB           4
`define INDEX_WIDTH         7

`define TAG_MSB             31
`define TAG_LSB             11
`define TAG_WIDTH           21

// Mã hóa 5 trạng thái FSM của Cache Controller
`define STATE_IDLE          3'b000   // Chờ yêu cầu từ CPU
`define STATE_COMPARE_TAG   3'b001   // So sánh Tag để kiểm tra Hit/Miss
`define STATE_WRITE_BACK    3'b010   // Ghi trả dòng bẩn (Dirty) về DRAM
`define STATE_FETCH_MEM     3'b011   // Đọc dòng 128-bit mới từ DRAM
`define STATE_REFILL_UPDATE 3'b100   // Nạp dòng mới vào Cache và trả CPU

`endif // CACHE_DEFINES_VH
