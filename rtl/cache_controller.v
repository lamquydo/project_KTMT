// =============================================================================
// Tên file   : cache_controller.v
// Chức năng  : Bộ điều khiển trung tâm FSM (Finite State Machine) 5 trạng thái
//              Điều khiển toàn bộ hoạt động của bộ nhớ đệm 4KB 2-Way Set-Associative
// Chính sách : Write-Back (Ghi trả khi bị đuổi), Write-Allocate (Ghi trượt thì nạp)
// Giáo trình : Kiến trúc máy tính (Patterson & Hennessy - Chương 5, Mục 5.3 - 5.4)
// =============================================================================

`timescale 1ns / 1ps
`include "cache_defines.vh"

module cache_controller #(
    parameter ADDR_WIDTH      = `ADDR_WIDTH,      // 32 bits
    parameter DATA_WIDTH      = `DATA_WIDTH,      // 32 bits
    parameter LINE_WIDTH      = `LINE_WIDTH,      // 128 bits
    parameter TAG_WIDTH       = `TAG_WIDTH,       // 21 bits
    parameter INDEX_WIDTH     = `INDEX_WIDTH,     // 7 bits
    parameter WORD_SEL_WIDTH  = `WORD_SEL_WIDTH   // 2 bits
)(
    // Xung nhịp và Reset hệ thống
    input  wire                      clk,
    input  wire                      rst_n,

    // -------------------------------------------------------------------------
    // 1. GIAO DIỆN GIAO TIẾP VỚI CPU (Bus 32-bit)
    // -------------------------------------------------------------------------
    input  wire                      cpu_req,     // 1: CPU yêu cầu truy cập bộ nhớ
    input  wire                      cpu_we,      // 0: Lệnh Đọc (Load), 1: Lệnh Ghi (Store)
    input  wire [ADDR_WIDTH-1:0]     cpu_addr,    // Địa chỉ byte 32-bit từ CPU
    input  wire [DATA_WIDTH-1:0]     cpu_wdata,   // Dữ liệu 32-bit CPU muốn ghi
    output reg                       cpu_ready,   // 1: Đã xong giao dịch, 0: Bắt CPU chờ (Stall)

    // -------------------------------------------------------------------------
    // 2. TÍN HIỆU TRẠNG THÁI NHẬN TỪ ĐƯỜNG DỮ LIỆU (Datapath) CỦA CACHE
    // -------------------------------------------------------------------------
    input  wire                      hit,         // 1: Trúng (Hit), 0: Trượt (Miss)
    input  wire                      hit_way,     // Đường trúng: 0 (Way 0) hoặc 1 (Way 1)
    input  wire                      valid0,      // Cờ Valid của Way 0
    input  wire                      valid1,      // Cờ Valid của Way 1
    input  wire                      dirty0,      // Cờ Dirty của Way 0
    input  wire                      dirty1,      // Cờ Dirty của Way 1
    input  wire [TAG_WIDTH-1:0]      tag0,        // Tag đọc ra từ Way 0
    input  wire [TAG_WIDTH-1:0]      tag1,        // Tag đọc ra từ Way 1
    input  wire [LINE_WIDTH-1:0]     line_out0,   // Dòng 128-bit đọc ra từ Way 0
    input  wire [LINE_WIDTH-1:0]     line_out1,   // Dòng 128-bit đọc ra từ Way 1
    input  wire                      victim_way,  // Đường nạn nhân được LRU chọn để thay thế (0 hoặc 1)

    // -------------------------------------------------------------------------
    // 3. GIAO DIỆN GIAO TIẾP VỚI BỘ NHỚ CHÍNH DRAM (Bus 128-bit)
    // -------------------------------------------------------------------------
    output reg                       mem_req,     // 1: Yêu cầu DRAM đọc/ghi
    output reg                       mem_we,      // 0: Đọc dòng từ DRAM, 1: Ghi trả dòng về DRAM
    output reg  [ADDR_WIDTH-1:0]     mem_addr,    // Địa chỉ khối căn chỉnh 16-byte gửi tới DRAM
    output reg  [LINE_WIDTH-1:0]     mem_wdata,   // Dữ liệu dòng 128-bit ghi trả về DRAM
    input  wire [LINE_WIDTH-1:0]     mem_rdata,   // Dữ liệu dòng 128-bit đọc được từ DRAM
    input  wire                      mem_ready,   // 1: DRAM báo đã hoàn thành (sau trễ 6 chu kỳ)

    // -------------------------------------------------------------------------
    // 4. TÍN HIỆU ĐIỀU KHIỂN GỬI SANG CÁC KHỐI DATAPATH NỘI BỘ
    // -------------------------------------------------------------------------
    output reg  [ADDR_WIDTH-1:0]     latched_addr,        // Thanh ghi chốt địa chỉ CPU
    output reg  [DATA_WIDTH-1:0]     latched_wdata,       // Thanh ghi chốt dữ liệu ghi từ CPU
    output reg                       latched_we,          // Thanh ghi chốt lệnh Đọc/Ghi
    output reg  [LINE_WIDTH-1:0]     refill_line,         // Dòng dữ liệu chuẩn bị ghi vào SRAM
    output reg                       sel_refill_data,     // 1: CPU nhận dữ liệu nạp từ DRAM, 0: từ SRAM

    // Điều khiển Way 0
    output reg                       tag_we0,             // Cho phép ghi Tag & Valid Way 0
    output reg                       dirty_we0,           // Cho phép cập nhật cờ Dirty Way 0
    output reg                       dirty_in0,           // Giá trị cờ Dirty nạp vào Way 0
    output reg                       line_we0,            // Cho phép ghi toàn dòng 128-bit Way 0
    output reg                       word_we0,            // Cho phép ghi 1 từ 32-bit vào Way 0

    // Điều khiển Way 1
    output reg                       tag_we1,             // Cho phép ghi Tag & Valid Way 1
    output reg                       dirty_we1,           // Cho phép cập nhật cờ Dirty Way 1
    output reg                       dirty_in1,           // Giá trị cờ Dirty nạp vào Way 1
    output reg                       line_we1,            // Cho phép ghi toàn dòng 128-bit Way 1
    output reg                       word_we1,            // Cho phép ghi 1 từ 32-bit vào Way 1

    // Điều khiển khối LRU
    output reg                       lru_update,          // Cho phép cập nhật trạng thái LRU
    output reg                       lru_access_way,      // Đường vừa được truy cập (0 hoặc 1)

    // Giám sát trạng thái FSM
    output wire [2:0]                fsm_state
);

    // -------------------------------------------------------------------------
    // KHAI BÁO CÁC THANH GHI NỘI BỘ CỦA BỘ ĐIỀU KHIỂN
    // -------------------------------------------------------------------------
    reg [2:0] state, next_state;  // Thanh ghi trạng thái hiện tại và trạng thái kế tiếp
    assign fsm_state = state;

    // Các thanh ghi chốt thông tin của đường nạn nhân (Victim) khi xảy ra Cache Miss
    reg                  latched_victim_way;   // Đường bị chọn làm nạn nhân (0 hoặc 1)
    reg [TAG_WIDTH-1:0]  latched_victim_tag;   // Tag của dòng nạn nhân (dùng ghép địa chỉ Write-Back)
    reg [LINE_WIDTH-1:0] latched_victim_data;  // Dữ liệu 128-bit của dòng nạn nhân cần ghi trả về DRAM
    reg [LINE_WIDTH-1:0] latched_mem_rdata;    // Dữ liệu 128-bit vừa đọc xong từ DRAM

    // Mạch tổ hợp kiểm tra xem dòng nạn nhân có bị "bẩn" (Dirty = 1) hay không:
    // Dòng chỉ cần Write-Back khi nó vừa hợp lệ (Valid=1) VÀ vừa bị sửa đổi (Dirty=1)
    wire victim_dirty = (victim_way == 1'b0) ? (valid0 && dirty0) : (valid1 && dirty1);


    // =========================================================================
    // KHỐI 1: CHUYỂN TRẠNG THÁI TUẦN TỰ & CHỐT DỮ LIỆU ĐẦU VÀO (Sequential Logic)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= `STATE_IDLE;
            latched_addr        <= {ADDR_WIDTH{1'b0}};
            latched_wdata       <= {DATA_WIDTH{1'b0}};
            latched_we          <= 1'b0;
            latched_victim_way  <= 1'b0;
            latched_victim_tag  <= {TAG_WIDTH{1'b0}};
            latched_victim_data <= {LINE_WIDTH{1'b0}};
            latched_mem_rdata   <= {LINE_WIDTH{1'b0}};
        end else begin
            state <= next_state;

            // Bước chốt yêu cầu CPU: Khi ở trạng thái rảnh (IDLE) và có yêu cầu mới
            if (state == `STATE_IDLE && cpu_req) begin
                latched_addr  <= cpu_addr;
                latched_wdata <= cpu_wdata;
                latched_we    <= cpu_we;
            end

            // Bước chốt dòng nạn nhân: Khi kiểm tra Tag thấy trượt (Miss)
            if (state == `STATE_COMPARE_TAG && !hit) begin
                latched_victim_way  <= victim_way;
                latched_victim_tag  <= (victim_way == 1'b0) ? tag0 : tag1;
                latched_victim_data <= (victim_way == 1'b0) ? line_out0 : line_out1;
            end

            // Bước chốt dữ liệu DRAM: Khi DRAM báo đã đọc xong dòng mới (mem_ready = 1)
            if (state == `STATE_FETCH_MEM && mem_ready) begin
                latched_mem_rdata <= mem_rdata;
            end
        end
    end


    // =========================================================================
    // KHỐI 2: TÍNH TOÁN TRẠNG THÁI KẾ TIẾP CỦA FSM (Next-State Combinational Logic)
    // Lưu đồ chuyển đổi 5 trạng thái bám sát giáo trình Patterson & Hennessy
    // =========================================================================
    always @(*) begin
        next_state = state;
        case (state)
            // -----------------------------------------------------------------
            // Trạng thái 0: IDLE (Chờ yêu cầu)
            // -----------------------------------------------------------------
            `STATE_IDLE: begin
                if (cpu_req) begin
                    next_state = `STATE_COMPARE_TAG; // Có yêu cầu -> sang so sánh Tag
                end
            end

            // -----------------------------------------------------------------
            // Trạng thái 1: COMPARE_TAG (So sánh Tag tìm Hit/Miss)
            // -----------------------------------------------------------------
            `STATE_COMPARE_TAG: begin
                if (hit) begin
                    // CACHE HIT: Hoàn thành ngay lập tức trong 1 chu kỳ!
                    next_state = `STATE_IDLE;
                end else begin
                    // CACHE MISS: Cần nạp dòng mới từ DRAM.
                    // Kiểm tra xem dòng nạn nhân có bị bẩn (Dirty) hay không:
                    if (victim_dirty) begin
                        // Nạn nhân bẩn -> Phải ghi trả về DRAM trước (Write-Back)
                        next_state = `STATE_WRITE_BACK;
                    end else begin
                        // Nạn nhân sạch -> Bỏ qua Write-Back, nạp luôn dòng mới từ DRAM!
                        next_state = `STATE_FETCH_MEM;
                    end
                end
            end

            // -----------------------------------------------------------------
            // Trạng thái 2: WRITE_BACK (Ghi trả khối bẩn 128-bit về DRAM)
            // -----------------------------------------------------------------
            `STATE_WRITE_BACK: begin
                if (mem_ready) begin
                    // DRAM đã ghi xong -> Chuyển sang đọc dòng mới mà CPU cần
                    next_state = `STATE_FETCH_MEM;
                end
            end

            // -----------------------------------------------------------------
            // Trạng thái 3: FETCH_MEM (Đọc khối mới 128-bit từ DRAM)
            // -----------------------------------------------------------------
            `STATE_FETCH_MEM: begin
                if (mem_ready) begin
                    // DRAM đã trả dữ liệu -> Chuyển sang ghi vào SRAM và trả lời CPU
                    next_state = `STATE_REFILL_UPDATE;
                end
            end

            // -----------------------------------------------------------------
            // Trạng thái 4: REFILL_UPDATE (Nạp vào Cache và trả dữ liệu cho CPU)
            // -----------------------------------------------------------------
            `STATE_REFILL_UPDATE: begin
                // Cập nhật xong mảng nhớ và báo CPU hoàn tất -> Quay lại IDLE
                next_state = `STATE_IDLE;
            end

            default: next_state = `STATE_IDLE;
        endcase
    end


    // =========================================================================
    // KHỐI 3: MẠCH TRỘN TỪ CHO CHÍNH SÁCH WRITE-ALLOCATE (Word Merging)
    // Khi Write Miss, ta lấy dòng 128-bit từ DRAM làm nền, sau đó thay thế đúng
    // từ 32-bit mà CPU vừa ghi vào vị trí tương ứng trước khi nạp vào Cache.
    // =========================================================================
    reg [LINE_WIDTH-1:0] merged_line;
    always @(*) begin
        merged_line = latched_mem_rdata; // Mặc định giữ nguyên 4 words từ DRAM
        case (latched_addr[`WORD_SEL_MSB:`WORD_SEL_LSB])
            2'b00: merged_line[31:0]   = latched_wdata; // Ghi đè vào Word 0
            2'b01: merged_line[63:32]  = latched_wdata; // Ghi đè vào Word 1
            2'b10: merged_line[95:64]  = latched_wdata; // Ghi đè vào Word 2
            2'b11: merged_line[127:96] = latched_wdata; // Ghi đè vào Word 3
            default: ;
        endcase
    end


    // =========================================================================
    // KHỐI 4: TẠO TÍN HIỆU ĐIỀU KHIỂN ĐẦU RA (Output Combinational Logic)
    // =========================================================================
    always @(*) begin
        // Giá trị mặc định (Tránh suy luận mạch chốt không mong muốn)
        cpu_ready       = 1'b0;
        sel_refill_data = 1'b0;
        mem_req         = 1'b0;
        mem_we          = 1'b0;
        mem_addr        = {ADDR_WIDTH{1'b0}};
        mem_wdata       = {LINE_WIDTH{1'b0}};
        refill_line     = latched_mem_rdata;

        tag_we0         = 1'b0;
        dirty_we0       = 1'b0;
        dirty_in0       = 1'b0;
        line_we0        = 1'b0;
        word_we0        = 1'b0;

        tag_we1         = 1'b0;
        dirty_we1       = 1'b0;
        dirty_in1       = 1'b0;
        line_we1        = 1'b0;
        word_we1        = 1'b0;

        lru_update      = 1'b0;
        lru_access_way  = 1'b0;

        case (state)
            `STATE_IDLE: begin
                // Không có hoạt động điều khiển ở trạng thái nghỉ
            end

            // -----------------------------------------------------------------
            // Xử lý khi ở COMPARE_TAG:
            // -----------------------------------------------------------------
            `STATE_COMPARE_TAG: begin
                if (hit) begin
                    cpu_ready      = 1'b1;         // Báo CPU giao dịch đã thành công
                    lru_update     = 1'b1;         // Cập nhật đường vừa dùng vào LRU
                    lru_access_way = hit_way;

                    // Nếu là lệnh Ghi trúng (Write Hit):
                    // Thực hiện chính sách Write-Back: Chỉ sửa trong Cache và bật Dirty = 1
                    if (latched_we) begin
                        if (hit_way == 1'b0) begin
                            word_we0  = 1'b1;      // Ghi từ 32-bit vào Way 0
                            dirty_we0 = 1'b1;
                            dirty_in0 = 1'b1;      // Đánh dấu dòng Way 0 bị bẩn
                        end else begin
                            word_we1  = 1'b1;      // Ghi từ 32-bit vào Way 1
                            dirty_we1 = 1'b1;
                            dirty_in1 = 1'b1;      // Đánh dấu dòng Way 1 bị bẩn
                        end
                    end
                end
            end

            // -----------------------------------------------------------------
            // Xử lý khi ở WRITE_BACK: Gửi dòng bẩn 128-bit về DRAM
            // -----------------------------------------------------------------
            `STATE_WRITE_BACK: begin
                // Tự ngắt yêu cầu mem_req khi mem_ready=1 để chống kích hoạt lệnh ảo
                mem_req   = ~mem_ready;
                mem_we    = 1'b1; // Lệnh ghi vào DRAM

                // Tái tạo địa chỉ vật lý 32-bit của dòng nạn nhân:
                // Ghép: {21-bit Tag nạn nhân, 7-bit Set Index, 4-bit 0000}
                mem_addr  = {latched_victim_tag, latched_addr[`INDEX_MSB:`INDEX_LSB], 4'b0000};
                mem_wdata = latched_victim_data; // Dữ liệu 128-bit của dòng nạn nhân
            end

            // -----------------------------------------------------------------
            // Xử lý khi ở FETCH_MEM: Đọc dòng mới 128-bit từ DRAM
            // -----------------------------------------------------------------
            `STATE_FETCH_MEM: begin
                mem_req   = ~mem_ready;
                mem_we    = 1'b0; // Lệnh đọc từ DRAM

                // Căn chỉnh địa chỉ khối 16-byte: Xóa 4 bit thấp về 0
                mem_addr  = {latched_addr[ADDR_WIDTH-1:`BLOCK_OFFSET_WIDTH], 4'b0000};
            end

            // -----------------------------------------------------------------
            // Xử lý khi ở REFILL_UPDATE: Nạp dòng vào SRAM & trả dữ liệu cho CPU
            // -----------------------------------------------------------------
            `STATE_REFILL_UPDATE: begin
                cpu_ready       = 1'b1; // Giải phóng CPU (hết Stall)
                sel_refill_data = 1'b1; // Nối thẳng dữ liệu nạp từ DRAM ra cpu_rdata
                lru_update      = 1'b1; // Cập nhật đường vừa nạp là MRU (Most Recently Used)
                lru_access_way  = latched_victim_way;

                // Trường hợp A: Nạp do Read Miss
                if (!latched_we) begin
                    refill_line = latched_mem_rdata; // Dữ liệu sạch nguyên bản từ DRAM
                    if (latched_victim_way == 1'b0) begin
                        tag_we0   = 1'b1; // Nạp Tag mới & Valid = 1 cho Way 0
                        dirty_we0 = 1'b1;
                        dirty_in0 = 1'b0; // Dòng sạch (Dirty = 0)
                        line_we0  = 1'b1; // Ghi toàn bộ 128-bit vào Way 0
                    end else begin
                        tag_we1   = 1'b1; // Nạp Tag mới & Valid = 1 cho Way 1
                        dirty_we1 = 1'b1;
                        dirty_in0 = 1'b0; // Dòng sạch (Dirty = 0)
                        line_we1  = 1'b1; // Ghi toàn bộ 128-bit vào Way 1
                    end
                end
                // Trường hợp B: Nạp do Write Miss (Chính sách Write-Allocate)
                else begin
                    refill_line = merged_line; // Dữ liệu đã trộn từ mới của CPU
                    if (latched_victim_way == 1'b0) begin
                        tag_we0   = 1'b1; // Nạp Tag mới & Valid = 1 cho Way 0
                        dirty_we0 = 1'b1;
                        dirty_in0 = 1'b1; // Đánh dấu bẩn (Dirty = 1) vì đã trộn từ mới!
                        line_we0  = 1'b1; // Ghi toàn bộ dòng đã trộn vào Way 0
                    end else begin
                        tag_we1   = 1'b1; // Nạp Tag mới & Valid = 1 cho Way 1
                        dirty_we1 = 1'b1;
                        dirty_in1 = 1'b1; // Đánh dấu bẩn (Dirty = 1) vì đã trộn từ mới!
                        line_we1  = 1'b1; // Ghi toàn bộ dòng đã trộn vào Way 1
                    end
                end
            end

            default: ;
        endcase
    end

endmodule
