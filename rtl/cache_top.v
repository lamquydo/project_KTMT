// =============================================================================
// Tên file   : cache_top.v
// Chức năng  : Module đỉnh (Top-Level Module) tích hợp toàn bộ hệ thống Cache 4KB
//              Kết nối: Controller, 2x Tag Array, 2x Data Array và Logic True LRU
// Kiến trúc  : Dung lượng 4KB, 2-Way Set-Associative, 128 Sets, 16 Bytes/Line
// Giáo trình : Kiến trúc máy tính (Patterson & Hennessy - Chương 5)
// =============================================================================

`timescale 1ns / 1ps
`include "cache_defines.vh"

module cache_top #(
    parameter ADDR_WIDTH      = `ADDR_WIDTH,      // 32 bits
    parameter DATA_WIDTH      = `DATA_WIDTH,      // 32 bits
    parameter LINE_WIDTH      = `LINE_WIDTH,      // 128 bits
    parameter TAG_WIDTH       = `TAG_WIDTH,       // 21 bits
    parameter INDEX_WIDTH     = `INDEX_WIDTH,     // 7 bits
    parameter WORD_SEL_WIDTH  = `WORD_SEL_WIDTH,  // 2 bits
    parameter NUM_SETS        = `NUM_SETS         // 128 Sets
)(
    input  wire                   clk,        // Xung nhịp hệ thống (Clock 100MHz)
    input  wire                   rst_n,      // Tín hiệu Reset tích cực mức thấp (Active-low)

    // -------------------------------------------------------------------------
    // 1. GIAO DIỆN KẾT NỐI VỚI CPU (Bus dữ liệu 32-bit)
    // -------------------------------------------------------------------------
    input  wire                   cpu_req,    // Tín hiệu xung yêu cầu từ CPU
    input  wire                   cpu_we,     // 0: Lệnh Đọc, 1: Lệnh Ghi
    input  wire [ADDR_WIDTH-1:0]  cpu_addr,   // Địa chỉ byte 32-bit CPU phát ra
    input  wire [DATA_WIDTH-1:0]  cpu_wdata,  // Dữ liệu 32-bit CPU muốn ghi
    output wire [DATA_WIDTH-1:0]  cpu_rdata,  // Dữ liệu 32-bit Cache trả về cho CPU
    output wire                   cpu_ready,  // 1: Hoàn thành, 0: CPU bị dừng chờ (Stall)

    // -------------------------------------------------------------------------
    // 2. GIAO DIỆN KẾT NỐI VỚI BỘ NHỚ CHÍNH DRAM (Bus khối 128-bit)
    // -------------------------------------------------------------------------
    output wire                   mem_req,    // Tín hiệu yêu cầu gửi sang DRAM
    output wire                   mem_we,     // 0: Đọc dòng, 1: Ghi trả dòng về DRAM
    output wire [ADDR_WIDTH-1:0]  mem_addr,   // Địa chỉ khối căn chỉnh 16-byte
    output wire [LINE_WIDTH-1:0]  mem_wdata,  // Khối 128-bit gửi xuống DRAM (Write-Back)
    input  wire [LINE_WIDTH-1:0]  mem_rdata,  // Khối 128-bit nạp từ DRAM về Cache
    input  wire                   mem_ready,  // DRAM phát xung báo hoàn tất (sau 6 chu kỳ)

    // -------------------------------------------------------------------------
    // 3. TÍN HIỆU ĐO LƯỜNG & GIÁM SÁT HIỆU NĂNG (Telemetry / Debug Outputs)
    // -------------------------------------------------------------------------
    output wire                   hit_out,    // Nhấp nháy = 1 khi Cache Hit
    output wire                   miss_out,   // Nhấp nháy = 1 khi Cache Miss
    output wire [2:0]             state_out   // Trạng thái hiện tại của FSM (0 đến 4)
);

    // -------------------------------------------------------------------------
    // DÂY DẪN KẾT NỐI NỘI BỘ (Internal Wires)
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0]     latched_addr;
    wire [DATA_WIDTH-1:0]     latched_wdata;
    wire                      latched_we;
    wire [LINE_WIDTH-1:0]     refill_line;
    wire                      sel_refill_data;

    // Cơ chế bảo vệ chỉ số Set Index:
    // Khi đang ở IDLE, lấy địa chỉ trực tiếp từ cpu_addr.
    // Ngay khi rời IDLE vào xử lý Miss, khóa chặt vào thanh ghi chốt latched_addr
    // để tránh bị lệch Set nếu CPU bên ngoài đổi tín hiệu trong lúc Stall!
    wire [INDEX_WIDTH-1:0]    current_index = (state_out == `STATE_IDLE) ? 
                                              cpu_addr[`INDEX_MSB:`INDEX_LSB] : 
                                              latched_addr[`INDEX_MSB:`INDEX_LSB];

    wire [WORD_SEL_WIDTH-1:0] current_word_idx = (state_out == `STATE_IDLE) ? 
                                                 cpu_addr[`WORD_SEL_MSB:`WORD_SEL_LSB] : 
                                                 latched_addr[`WORD_SEL_MSB:`WORD_SEL_LSB];

    // Dữ liệu đọc ra từ 2 mảng Tag Array và 2 mảng Data Array
    wire [TAG_WIDTH-1:0]      tag0, tag1;
    wire                      valid0, valid1;
    wire                      dirty0, dirty1;
    wire [LINE_WIDTH-1:0]     line_out0, line_out1;
    wire [DATA_WIDTH-1:0]     word_out0, word_out1;

    // Các tín hiệu cho phép ghi từ Bộ điều khiển Controller
    wire tag_we0, dirty_we0, dirty_in0, line_we0, word_we0;
    wire tag_we1, dirty_we1, dirty_in1, line_we1, word_we1;

    // Các tín hiệu của khối quản lý thuật toán thay thế True LRU
    wire lru_update;
    wire lru_access_way;
    wire lru_bit;
    wire victim_way;


    // =========================================================================
    // KHỐI SO SÁNH TAG SONG SONG & PHÁT HIỆN HIT / MISS (Hình 5.18 Giáo trình)
    // =========================================================================
    // Trường Tag cần tìm kiếm: Lấy 21 bit cao của địa chỉ chốt
    wire [TAG_WIDTH-1:0] req_tag = latched_addr[`TAG_MSB:`TAG_LSB];

    // So sánh song song trên cả 2 Way:
    // Trúng Way 0 khi: Way 0 đã có dữ liệu hợp lệ (valid0=1) VÀ Tag của Way 0 trùng khớp
    wire hit0 = valid0 && (tag0 == req_tag);

    // Trúng Way 1 khi: Way 1 đã có dữ liệu hợp lệ (valid1=1) VÀ Tag của Way 1 trùng khớp
    wire hit1 = valid1 && (tag1 == req_tag);

    // Cache Hit khi trúng ở một trong hai Way
    wire hit  = hit0 || hit1;

    // Đường trúng: 0 nếu trúng ở Way 0, 1 nếu trúng ở Way 1
    wire hit_way = hit1;

    // Tín hiệu báo ra ngoài để Testbench đếm số lần Hit/Miss
    assign hit_out  = (state_out == `STATE_COMPARE_TAG) && hit;
    assign miss_out = (state_out == `STATE_COMPARE_TAG) && !hit;


    // =========================================================================
    // MẠCH CHỌN DỮ LIỆU ĐỌC TRẢ VỀ CHO CPU (Read Multiplexers)
    // =========================================================================
    // Khi Hit: Chọn từ 32-bit của Way 0 hoặc Way 1 tùy vào đường trúng
    wire [DATA_WIDTH-1:0] hit_rdata = (hit0) ? word_out0 : word_out1;

    // Mạch Bypass: Trích xuất trực tiếp từ 32-bit từ dòng vừa nạp từ DRAM
    // giúp trả dữ liệu cho CPU ngay trong chu kỳ REFILL_UPDATE mà không phải đợi thêm 1 chu kỳ!
    reg [DATA_WIDTH-1:0] refill_rdata;
    always @(*) begin
        case (latched_addr[`WORD_SEL_MSB:`WORD_SEL_LSB])
            2'b00: refill_rdata = refill_line[31:0];
            2'b01: refill_rdata = refill_line[63:32];
            2'b10: refill_rdata = refill_line[95:64];
            2'b11: refill_rdata = refill_line[127:96];
            default: refill_rdata = refill_line[31:0];
        endcase
    end

    // Dữ liệu cuối cùng xuất ra cổng cpu_rdata:
    // Nếu vừa nạp xong (sel_refill_data = 1) -> lấy từ refill_rdata; còn lại lấy từ hit_rdata
    assign cpu_rdata = (sel_refill_data) ? refill_rdata : hit_rdata;


    // =========================================================================
    // KHỞI TẠO VÀ GHÉP NỐI CÁC THỰC THỂ CON (Module Instantiations)
    // =========================================================================

    // 1. Mảng Thẻ địa chỉ của Way 0 (Tag Array Way 0)
    tag_array #(
        .NUM_SETS(NUM_SETS),
        .INDEX_WIDTH(INDEX_WIDTH),
        .TAG_WIDTH(TAG_WIDTH)
    ) u_tag_way0 (
        .clk(clk),
        .rst_n(rst_n),
        .index(current_index),
        .tag_we(tag_we0),
        .tag_in(req_tag),
        .dirty_we(dirty_we0),
        .dirty_in(dirty_in0),
        .tag_out(tag0),
        .valid_out(valid0),
        .dirty_out(dirty0)
    );

    // 2. Mảng Dữ liệu của Way 0 (Data Array Way 0: 2 KB)
    data_array #(
        .NUM_SETS(NUM_SETS),
        .INDEX_WIDTH(INDEX_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .WORD_SEL_WIDTH(WORD_SEL_WIDTH)
    ) u_data_way0 (
        .clk(clk),
        .rst_n(rst_n),
        .index(current_index),
        .word_idx(current_word_idx),
        .line_we(line_we0),
        .line_in(refill_line),
        .word_we(word_we0),
        .word_in(latched_wdata),
        .line_out(line_out0),
        .word_out(word_out0)
    );

    // 3. Mảng Thẻ địa chỉ của Way 1 (Tag Array Way 1)
    tag_array #(
        .NUM_SETS(NUM_SETS),
        .INDEX_WIDTH(INDEX_WIDTH),
        .TAG_WIDTH(TAG_WIDTH)
    ) u_tag_way1 (
        .clk(clk),
        .rst_n(rst_n),
        .index(current_index),
        .tag_we(tag_we1),
        .tag_in(req_tag),
        .dirty_we(dirty_we1),
        .dirty_in(dirty_in1),
        .tag_out(tag1),
        .valid_out(valid1),
        .dirty_out(dirty1)
    );

    // 4. Mảng Dữ liệu của Way 1 (Data Array Way 1: 2 KB)
    data_array #(
        .NUM_SETS(NUM_SETS),
        .INDEX_WIDTH(INDEX_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .WORD_SEL_WIDTH(WORD_SEL_WIDTH)
    ) u_data_way1 (
        .clk(clk),
        .rst_n(rst_n),
        .index(current_index),
        .word_idx(current_word_idx),
        .line_we(line_we1),
        .line_in(refill_line),
        .word_we(word_we1),
        .word_in(latched_wdata),
        .line_out(line_out1),
        .word_out(word_out1)
    );

    // 5. Khối Quản lý Thuật toán Thay thế True LRU (1-bit/Set)
    lru_logic #(
        .NUM_SETS(NUM_SETS),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) u_lru_logic (
        .clk(clk),
        .rst_n(rst_n),
        .index(current_index),
        .valid0(valid0),
        .valid1(valid1),
        .lru_update(lru_update),
        .access_way(lru_access_way),
        .lru_bit(lru_bit),
        .victim_way(victim_way)
    );

    // 6. Bộ điều khiển trung tâm (FSM Controller)
    cache_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH),
        .WORD_SEL_WIDTH(WORD_SEL_WIDTH)
    ) u_controller (
        .clk(clk),
        .rst_n(rst_n),

        // Giao tiếp CPU
        .cpu_req(cpu_req),
        .cpu_we(cpu_we),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_ready(cpu_ready),

        // Trạng thái từ Datapath
        .hit(hit),
        .hit_way(hit_way),
        .valid0(valid0),
        .valid1(valid1),
        .dirty0(dirty0),
        .dirty1(dirty1),
        .tag0(tag0),
        .tag1(tag1),
        .line_out0(line_out0),
        .line_out1(line_out1),
        .victim_way(victim_way),

        // Giao tiếp DRAM
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),

        // Điều khiển Datapath
        .latched_addr(latched_addr),
        .latched_wdata(latched_wdata),
        .latched_we(latched_we),
        .refill_line(refill_line),
        .sel_refill_data(sel_refill_data),

        .tag_we0(tag_we0),
        .dirty_we0(dirty_we0),
        .dirty_in0(dirty_in0),
        .line_we0(line_we0),
        .word_we0(word_we0),

        .tag_we1(tag_we1),
        .dirty_we1(dirty_we1),
        .dirty_in1(dirty_in1),
        .line_we1(line_we1),
        .word_we1(word_we1),

        .lru_update(lru_update),
        .lru_access_way(lru_access_way),

        .fsm_state(state_out)
    );

endmodule
