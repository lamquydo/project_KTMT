// main_memory_model.v - Mô hình DRAM giả lập (256KB, bus 128-bit, trễ 6 chu kỳ)

`timescale 1ns / 1ps
`include "../rtl/cache_defines.vh"

module main_memory_model #(
    parameter LATENCY_CYCLES = 6,
    parameter MEM_LINES      = 16384  // 16384 dòng x 16B = 256 KB
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   mem_req,
    input  wire                   mem_we,
    input  wire [`ADDR_WIDTH-1:0] mem_addr,
    input  wire [`LINE_WIDTH-1:0] mem_wdata,
    output reg  [`LINE_WIDTH-1:0] mem_rdata,
    output reg                    mem_ready
);

    reg [`LINE_WIDTH-1:0] mem_storage [0:MEM_LINES-1];

    reg [3:0]              latency_counter;
    reg                    busy;
    reg                    latched_we;
    reg [13:0]             latched_line_idx;
    reg [`LINE_WIDTH-1:0]  latched_wdata;

    // Bỏ 4 bit offset, lấy 14 bit địa chỉ dòng
    wire [13:0] line_idx = mem_addr[17:4];

    // Khởi tạo dữ liệu mẫu dạng 0x1000_0000 | Addr để dễ đối chiếu khi test
    integer i;
    reg [31:0] init_w0, init_w1, init_w2, init_w3;
    initial begin
        for (i = 0; i < MEM_LINES; i = i + 1) begin
            init_w0 = 32'h1000_0000 | (i * 16 + 0);
            init_w1 = 32'h1000_0000 | (i * 16 + 4);
            init_w2 = 32'h1000_0000 | (i * 16 + 8);
            init_w3 = 32'h1000_0000 | (i * 16 + 12);
            mem_storage[i] = {init_w3, init_w2, init_w1, init_w0};
        end
    end

    // Mô phỏng độ trễ truy cập DRAM và phát xung mem_ready 1 chu kỳ khi xong
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
            mem_ready <= 1'b0;

            if (!busy) begin
                // Chỉ nhận yêu cầu mới khi mem_ready đã hạ về 0
                if (mem_req && !mem_ready) begin
                    busy             <= 1'b1;
                    latency_counter  <= 4'd1;
                    latched_we       <= mem_we;
                    latched_line_idx <= line_idx;
                    latched_wdata    <= mem_wdata;
                end
            end else begin
                if (latency_counter < LATENCY_CYCLES) begin
                    latency_counter <= latency_counter + 1'b1;
                end else begin
                    busy            <= 1'b0;
                    mem_ready       <= 1'b1;
                    latency_counter <= 4'd0;

                    if (latched_we) begin
                        mem_storage[latched_line_idx] <= latched_wdata;
                    end else begin
                        mem_rdata <= mem_storage[latched_line_idx];
                    end
                end
            end
        end
    end

endmodule
