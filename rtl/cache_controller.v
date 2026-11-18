// cache_controller.v - Bộ điều khiển FSM 5 trạng thái (Write-Back, Write-Allocate)

`timescale 1ns / 1ps
`include "cache_defines.vh"

module cache_controller #(
    parameter ADDR_WIDTH      = `ADDR_WIDTH,
    parameter DATA_WIDTH      = `DATA_WIDTH,
    parameter LINE_WIDTH      = `LINE_WIDTH,
    parameter TAG_WIDTH       = `TAG_WIDTH,
    parameter INDEX_WIDTH     = `INDEX_WIDTH,
    parameter WORD_SEL_WIDTH  = `WORD_SEL_WIDTH
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // Giao diện CPU
    input  wire                      cpu_req,
    input  wire                      cpu_we,
    input  wire [ADDR_WIDTH-1:0]     cpu_addr,
    input  wire [DATA_WIDTH-1:0]     cpu_wdata,
    output reg                       cpu_ready,

    // Trạng thái từ Datapath
    input  wire                      hit,
    input  wire                      hit_way,
    input  wire                      valid0,
    input  wire                      valid1,
    input  wire                      dirty0,
    input  wire                      dirty1,
    input  wire [TAG_WIDTH-1:0]      tag0,
    input  wire [TAG_WIDTH-1:0]      tag1,
    input  wire [LINE_WIDTH-1:0]     line_out0,
    input  wire [LINE_WIDTH-1:0]     line_out1,
    input  wire                      victim_way,

    // Giao diện DRAM
    output reg                       mem_req,
    output reg                       mem_we,
    output reg  [ADDR_WIDTH-1:0]     mem_addr,
    output reg  [LINE_WIDTH-1:0]     mem_wdata,
    input  wire [LINE_WIDTH-1:0]     mem_rdata,
    input  wire                      mem_ready,

    // Điều khiển Datapath nội bộ
    output reg  [ADDR_WIDTH-1:0]     latched_addr,
    output reg  [DATA_WIDTH-1:0]     latched_wdata,
    output reg                       latched_we,
    output reg  [LINE_WIDTH-1:0]     refill_line,
    output reg                       sel_refill_data,

    output reg                       tag_we0,
    output reg                       dirty_we0,
    output reg                       dirty_in0,
    output reg                       line_we0,
    output reg                       word_we0,

    output reg                       tag_we1,
    output reg                       dirty_we1,
    output reg                       dirty_in1,
    output reg                       line_we1,
    output reg                       word_we1,

    output reg                       lru_update,
    output reg                       lru_access_way,

    output wire [2:0]                fsm_state
);

    reg [2:0] state, next_state;
    assign fsm_state = state;

    // Thanh ghi chốt thông tin nạn nhân khi Miss và dữ liệu đọc về từ DRAM
    reg                  latched_victim_way;
    reg [TAG_WIDTH-1:0]  latched_victim_tag;
    reg [LINE_WIDTH-1:0] latched_victim_data;
    reg [LINE_WIDTH-1:0] latched_mem_rdata;

    // Chỉ cần Write-Back khi dòng nạn nhân đang hợp lệ (Valid=1) và bị bẩn (Dirty=1)
    wire victim_dirty = (victim_way == 1'b0) ? (valid0 && dirty0) : (valid1 && dirty1);


    // 1. Mạch tuần tự: chuyển trạng thái FSM và chốt tín hiệu quan trọng
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

            // Chốt yêu cầu CPU ngay khi bắt đầu giao dịch
            if (state == `STATE_IDLE && cpu_req) begin
                latched_addr  <= cpu_addr;
                latched_wdata <= cpu_wdata;
                latched_we    <= cpu_we;
            end

            // Chốt thông tin Victim trước khi ghi trả DRAM hoặc nạp mới
            if (state == `STATE_COMPARE_TAG && !hit) begin
                latched_victim_way  <= victim_way;
                latched_victim_tag  <= (victim_way == 1'b0) ? tag0 : tag1;
                latched_victim_data <= (victim_way == 1'b0) ? line_out0 : line_out1;
            end

            if (state == `STATE_FETCH_MEM && mem_ready) begin
                latched_mem_rdata <= mem_rdata;
            end
        end
    end


    // 2. Mạch tổ hợp: tính trạng thái kế tiếp của FSM
    always @(*) begin
        next_state = state;
        case (state)
            `STATE_IDLE: begin
                if (cpu_req) begin
                    next_state = `STATE_COMPARE_TAG;
                end
            end

            `STATE_COMPARE_TAG: begin
                if (hit) begin
                    next_state = `STATE_IDLE;
                end else begin
                    // Nếu nạn nhân bẩn thì Write-Back trước, sạch thì nạp luôn từ DRAM
                    if (victim_dirty) begin
                        next_state = `STATE_WRITE_BACK;
                    end else begin
                        next_state = `STATE_FETCH_MEM;
                    end
                end
            end

            `STATE_WRITE_BACK: begin
                if (mem_ready) begin
                    next_state = `STATE_FETCH_MEM;
                end
            end

            `STATE_FETCH_MEM: begin
                if (mem_ready) begin
                    next_state = `STATE_REFILL_UPDATE;
                end
            end

            `STATE_REFILL_UPDATE: begin
                next_state = `STATE_IDLE;
            end

            default: next_state = `STATE_IDLE;
        endcase
    end


    // 3. Mạch trộn Word cho Write-Allocate: ghép Word 32-bit của CPU vào dòng 128-bit từ DRAM
    reg [LINE_WIDTH-1:0] merged_line;
    always @(*) begin
        merged_line = latched_mem_rdata;
        case (latched_addr[`WORD_SEL_MSB:`WORD_SEL_LSB])
            2'b00: merged_line[31:0]   = latched_wdata;
            2'b01: merged_line[63:32]  = latched_wdata;
            2'b10: merged_line[95:64]  = latched_wdata;
            2'b11: merged_line[127:96] = latched_wdata;
            default: ;
        endcase
    end


    // 4. Mạch tổ hợp: tạo các tín hiệu điều khiển đầu ra theo trạng thái hiện tại
    always @(*) begin
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
            end

            `STATE_COMPARE_TAG: begin
                if (hit) begin
                    cpu_ready      = 1'b1;
                    lru_update     = 1'b1;
                    lru_access_way = hit_way;

                    // Write Hit: chỉ ghi vào Cache và bật Dirty = 1 (Write-Back)
                    if (latched_we) begin
                        if (hit_way == 1'b0) begin
                            word_we0  = 1'b1;
                            dirty_we0 = 1'b1;
                            dirty_in0 = 1'b1;
                        end else begin
                            word_we1  = 1'b1;
                            dirty_we1 = 1'b1;
                            dirty_in1 = 1'b1;
                        end
                    end
                end
            end

            `STATE_WRITE_BACK: begin
                // Ngắt mem_req ngay khi mem_ready = 1 để tránh kích hoạt giao dịch DRAM ảo
                mem_req   = ~mem_ready;
                mem_we    = 1'b1;
                // Ghép lại địa chỉ 16B-aligned của dòng nạn nhân từ Tag cũ và Index hiện tại
                mem_addr  = {latched_victim_tag, latched_addr[`INDEX_MSB:`INDEX_LSB], 4'b0000};
                mem_wdata = latched_victim_data;
            end

            `STATE_FETCH_MEM: begin
                mem_req   = ~mem_ready;
                mem_we    = 1'b0;
                // Căn chỉnh địa chỉ khối 16-byte (xóa 4 bit thấp)
                mem_addr  = {latched_addr[ADDR_WIDTH-1:`BLOCK_OFFSET_WIDTH], 4'b0000};
            end

            `STATE_REFILL_UPDATE: begin
                cpu_ready       = 1'b1;
                sel_refill_data = 1'b1;
                lru_update      = 1'b1;
                lru_access_way  = latched_victim_way;

                // Read Miss: nạp nguyên dòng từ DRAM, Dirty = 0
                if (!latched_we) begin
                    refill_line = latched_mem_rdata;
                    if (latched_victim_way == 1'b0) begin
                        tag_we0   = 1'b1;
                        dirty_we0 = 1'b1;
                        dirty_in0 = 1'b0;
                        line_we0  = 1'b1;
                    end else begin
                        tag_we1   = 1'b1;
                        dirty_we1 = 1'b1;
                        dirty_in1 = 1'b0;
                        line_we1  = 1'b1;
                    end
                end
                // Write Miss (Write-Allocate): nạp dòng đã trộn Word mới, bật Dirty = 1
                else begin
                    refill_line = merged_line;
                    if (latched_victim_way == 1'b0) begin
                        tag_we0   = 1'b1;
                        dirty_we0 = 1'b1;
                        dirty_in0 = 1'b1;
                        line_we0  = 1'b1;
                    end else begin
                        tag_we1   = 1'b1;
                        dirty_we1 = 1'b1;
                        dirty_in1 = 1'b1;
                        line_we1  = 1'b1;
                    end
                end
            end

            default: ;
        endcase
    end

endmodule
