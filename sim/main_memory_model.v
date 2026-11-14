// =============================================================================
// Tên file   : main_memory_model.v
// Chức năng  : Mô hình hành vi Bộ nhớ chính DRAM (Behavioral DRAM Model)
// Đặc điểm   : 
//   - Dung lượng giả lập: 256 KB (16,384 dòng nhớ x 128-bit/dòng)
//   - Bus khối rộng 128-bit (16 Bytes/lần truy cập)
//   - Độ trễ cấu hình được: Mặc định LATENCY_CYCLES = 6 chu kỳ
//   - Khởi tạo sẵn dữ liệu có quy luật: Word = 0x1000_0000 | Addr
// Giáo trình : Kiến trúc máy tính (Patterson & Hennessy - Chương 5)
// =============================================================================

`timescale 1ns / 1ps
`include "../rtl/cache_defines.vh"

module main_memory_model #(
    parameter LATENCY_CYCLES = 6,     // Độ trễ truy cập DRAM (mặc định 6 chu kỳ xung nhịp)
    parameter MEM_LINES      = 16384  // 16,384 dòng x 16 Bytes = 256 KB không gian nhớ
)(
    input  wire                   clk,        // Xung nhịp hệ thống
    input  wire                   rst_n,      // Reset tích cực mức thấp

    // Giao diện bus bộ nhớ kết nối với Cache Controller
    input  wire                   mem_req,    // 1: Cache yêu cầu giao dịch
    input  wire                   mem_we,     // 0: Đọc dòng từ DRAM, 1: Ghi trả dòng về DRAM
    input  wire [`ADDR_WIDTH-1:0] mem_addr,   // Địa chỉ byte căn chỉnh 16-byte (4 bit thấp = 0)
    input  wire [`LINE_WIDTH-1:0] mem_wdata,  // Dữ liệu dòng 128-bit Cache ghi trả về DRAM
    output reg  [`LINE_WIDTH-1:0] mem_rdata,  // Dữ liệu dòng 128-bit DRAM trả về cho Cache
    output reg                    mem_ready   // Xung báo đã hoàn thành (1 chu kỳ)
);

    // -------------------------------------------------------------------------
    // KHÔNG GIAN LƯU TRỮ DRAM: 16,384 dòng nhớ 128-bit (256 KB)
    // -------------------------------------------------------------------------
    reg [`LINE_WIDTH-1:0] mem_storage [0:MEM_LINES-1];

    reg [3:0]              latency_counter;   // Bộ đếm chu kỳ trễ
    reg                    busy;              // Cờ báo DRAM đang bận xử lý
    reg                    latched_we;        // Chốt lệnh Đọc/Ghi
    reg [13:0]             latched_line_idx;  // Chốt chỉ số dòng bộ nhớ
    reg [`LINE_WIDTH-1:0]  latched_wdata;     // Chốt dữ liệu ghi

    // Trích xuất chỉ số dòng DRAM: Bỏ 4 bit thấp (Block Offset), lấy 14 bit [17:4]
    wire [13:0] line_idx = mem_addr[17:4];

    // -------------------------------------------------------------------------
    // KHỞI TẠO DỮ LIỆU NỀN CÓ QUY LUẬT (Deterministic Test Pattern)
    // Giúp sinh viên và giảng viên nhìn vào giá trị dữ liệu là biết ngay thuộc dòng nào!
    // -------------------------------------------------------------------------
    integer i;
    reg [31:0] init_w0, init_w1, init_w2, init_w3;
    initial begin
        for (i = 0; i < MEM_LINES; i = i + 1) begin
            init_w0 = 32'h1000_0000 | (i * 16 + 0);  // Word 0 tại offset 0
            init_w1 = 32'h1000_0000 | (i * 16 + 4);  // Word 1 tại offset 4
            init_w2 = 32'h1000_0000 | (i * 16 + 8);  // Word 2 tại offset 8
            init_w3 = 32'h1000_0000 | (i * 16 + 12); // Word 3 tại offset 12
            mem_storage[i] = {init_w3, init_w2, init_w1, init_w0};
        end
    end

    // -------------------------------------------------------------------------
    // MẠCH MÔ PHỎNG ĐỘ TRỄ VÀ ĐỌC/GHI DRAM
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latency_counter  <= 4'd0;
            busy             <= 1'b0;
            latched_we       <= 1'b0;
            latched_line_idx <= 14'd0;
            latched_wdata    <= {`LINE_WIDTH{1'b0}};
            mem_ready        <= 1'b0;
            mem_rdata        <= {`LINE_WIDTH{1'b0}};
        end else begin
            mem_ready <= 1'b0; // Mặc định chỉ phát xung trong đúng 1 chu kỳ

            if (!busy) begin
                // Khi DRAM đang rảnh và nhận được yêu cầu mới từ Cache:
                if (mem_req && !mem_ready) begin
                    busy             <= 1'b1;         // Bắt đầu chu kỳ bận
                    latency_counter  <= 4'd1;         // Khởi động bộ đếm
                    latched_we       <= mem_we;       // Chốt lệnh
                    latched_line_idx <= line_idx;     // Chốt địa chỉ
                    latched_wdata    <= mem_wdata;    // Chốt dữ liệu
                end
            end else begin
                // Đang trong thời gian đếm trễ
                if (latency_counter < LATENCY_CYCLES) begin
                    latency_counter <= latency_counter + 1'b1;
                end else begin
                    // Đã đếm đủ số chu kỳ trễ quy định: Hoàn tất giao dịch
                    busy            <= 1'b0;
                    mem_ready       <= 1'b1;          // Bật cờ báo hoàn thành
                    latency_counter <= 4'd0;

                    if (latched_we) begin
                        // Thao tác Ghi vào DRAM (Write-Back)
                        mem_storage[latched_line_idx] <= latched_wdata;
                    end else begin
                        // Thao tác Đọc từ DRAM (Refill)
                        mem_rdata <= mem_storage[latched_line_idx];
                    end
                end
            end
        end
    end

endmodule
