// =============================================================================
// File: cache_defines.vh
// Description: Global Parameters and Header Definitions for 4KB 2-Way Set-Associative Cache
// Architecture: 32-bit Address, 4KB Total Capacity, 16 Bytes/Line, 128 Sets, 2 Ways
// Course: Computer Architecture (Kien Truc May Tinh)
// =============================================================================

`ifndef CACHE_DEFINES_VH
`define CACHE_DEFINES_VH

// Architecture Sizing Parameters
`define ADDR_WIDTH          32
`define DATA_WIDTH          32
`define LINE_BYTES          16
`define LINE_WIDTH          128    // 16 bytes * 8 bits
`define WORDS_PER_LINE      4
`define NUM_WAYS            2
`define NUM_SETS            128

// Address Bit Fields Decomposition
// Address [31:0] is divided into:
// | Tag: 21 bits [31:11] | Index: 7 bits [10:4] | Word: 2 bits [3:2] | Byte: 2 bits [1:0] |
`define TAG_MSB             31
`define TAG_LSB             11
`define TAG_WIDTH           21

`define INDEX_MSB           10
`define INDEX_LSB           4
`define INDEX_WIDTH         7

`define WORD_SEL_MSB        3
`define WORD_SEL_LSB        2
`define WORD_SEL_WIDTH      2

`define BYTE_OFFSET_MSB     1
`define BYTE_OFFSET_LSB     0
`define BYTE_OFFSET_WIDTH   2

`define BLOCK_OFFSET_MSB    3
`define BLOCK_OFFSET_LSB    0
`define BLOCK_OFFSET_WIDTH  4

// FSM States Encoding (3-bit state)
`define STATE_IDLE          3'b000
`define STATE_COMPARE_TAG   3'b001
`define STATE_WRITE_BACK    3'b010
`define STATE_FETCH_MEM     3'b011
`define STATE_REFILL_UPDATE 3'b100

`endif // CACHE_DEFINES_VH
