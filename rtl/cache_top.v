// cache_top.v - Module đỉnh kết nối Controller, 2 Way Tag/Data Array và LRU

`timescale 1ns / 1ps
`include "cache_defines.vh"

module cache_top #(
    parameter ADDR_WIDTH      = `ADDR_WIDTH,
    parameter DATA_WIDTH      = `DATA_WIDTH,
    parameter LINE_WIDTH      = `LINE_WIDTH,
    parameter TAG_WIDTH       = `TAG_WIDTH,
    parameter INDEX_WIDTH     = `INDEX_WIDTH,
    parameter WORD_SEL_WIDTH  = `WORD_SEL_WIDTH,
    parameter NUM_SETS        = `NUM_SETS
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Giao diện CPU (32-bit)
    input  wire                   cpu_req,
    input  wire                   cpu_we,
    input  wire [ADDR_WIDTH-1:0]  cpu_addr,
    input  wire [DATA_WIDTH-1:0]  cpu_wdata,
    output wire [DATA_WIDTH-1:0]  cpu_rdata,
    output wire                   cpu_ready,

    // Giao diện DRAM (128-bit)
    output wire                   mem_req,
    output wire                   mem_we,
    output wire [ADDR_WIDTH-1:0]  mem_addr,
    output wire [LINE_WIDTH-1:0]  mem_wdata,
    input  wire [LINE_WIDTH-1:0]  mem_rdata,
    input  wire                   mem_ready,

    // Tín hiệu debug / đo hiệu năng cho testbench
    output wire                   hit_out,
    output wire                   miss_out,
    output wire [2:0]             state_out
);

    wire [ADDR_WIDTH-1:0]     latched_addr;
    wire [DATA_WIDTH-1:0]     latched_wdata;
    wire                      latched_we;
    wire [LINE_WIDTH-1:0]     refill_line;
    wire                      sel_refill_data;

    // Lúc IDLE lấy địa chỉ trực tiếp từ cpu_addr; khi đang xử lý Miss dùng latched_addr để tránh lệch Set
    wire [INDEX_WIDTH-1:0]    current_index = (state_out == `STATE_IDLE) ? 
                                              cpu_addr[`INDEX_MSB:`INDEX_LSB] : 
                                              latched_addr[`INDEX_MSB:`INDEX_LSB];

    wire [WORD_SEL_WIDTH-1:0] current_word_idx = (state_out == `STATE_IDLE) ? 
                                                 cpu_addr[`WORD_SEL_MSB:`WORD_SEL_LSB] : 
                                                 latched_addr[`WORD_SEL_MSB:`WORD_SEL_LSB];

    wire [TAG_WIDTH-1:0]      tag0, tag1;
    wire                      valid0, valid1;
    wire                      dirty0, dirty1;
    wire [LINE_WIDTH-1:0]     line_out0, line_out1;
    wire [DATA_WIDTH-1:0]     word_out0, word_out1;

    wire tag_we0, dirty_we0, dirty_in0, line_we0, word_we0;
    wire tag_we1, dirty_we1, dirty_in1, line_we1, word_we1;

    wire lru_update;
    wire lru_access_way;
    wire lru_bit;
    wire victim_way;


    // So sánh Tag song song trên cả 2 Way
    wire [TAG_WIDTH-1:0] req_tag = latched_addr[`TAG_MSB:`TAG_LSB];
    wire hit0 = valid0 && (tag0 == req_tag);
    wire hit1 = valid1 && (tag1 == req_tag);
    wire hit  = hit0 || hit1;
    wire hit_way = hit1;

    assign hit_out  = (state_out == `STATE_COMPARE_TAG) && hit;
    assign miss_out = (state_out == `STATE_COMPARE_TAG) && !hit;


    // Mạch chọn dữ liệu đọc trả về CPU
    wire [DATA_WIDTH-1:0] hit_rdata = (hit0) ? word_out0 : word_out1;

    // Bypass dữ liệu vừa nạp từ DRAM ra thẳng cpu_rdata tại chu kỳ REFILL_UPDATE (đỡ trễ 1 chu kỳ)
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

    assign cpu_rdata = (sel_refill_data) ? refill_rdata : hit_rdata;


    // Khởi tạo Way 0 (Tag Array + Data Array 2KB)
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

    // Khởi tạo Way 1 (Tag Array + Data Array 2KB)
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

    // Khối quản lý thay thế True LRU
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

    // Bộ điều khiển trung tâm FSM 5 trạng thái
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

        .cpu_req(cpu_req),
        .cpu_we(cpu_we),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_ready(cpu_ready),

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

        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),

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
