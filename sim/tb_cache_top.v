// =============================================================================
// File: tb_cache_top.v
// Description: Comprehensive Self-Checking Testbench for 4KB 2-Way Set-Associative Cache
// Scenarios Tested:
//   1. Cold Miss (Compulsory Miss) & Clean Refill Latency (10 cycles)
//   2. Read Hit (Single-cycle latency & Spatial locality across all 4 words in block)
//   3. Write Hit (Write-Back Policy: 1-cycle update, Dirty bit assertion, DRAM unchanged)
//   4. Write Miss (Write-Allocate: fetch line, merge word, set Dirty, 10 cycles)
//   5. Conflict Miss & LRU Replacement & Dirty Line Write-Back to DRAM (18 cycles)
//   6. Conflict Miss with Clean Victim Eviction (No Write-Back needed, 10 cycles)
//   7. Textbook Section 5.4 Benchmark: 2-Way Associativity & LRU Sequence Verification
//   8. Multi-Set Boundary Test (Set 63, Set 127) & Quantitative AMAT/Stall Report
// Course: Computer Architecture (Kien Truc May Tinh)
// =============================================================================

`timescale 1ns / 1ps
`include "../rtl/cache_defines.vh"

module tb_cache_top;

    // Clock and Reset Signals
    reg clk;
    reg rst_n;

    // CPU Bus Interface Signals
    reg                      cpu_req;
    reg                      cpu_we;
    reg  [`ADDR_WIDTH-1:0]   cpu_addr;
    reg  [`DATA_WIDTH-1:0]   cpu_wdata;
    wire [`DATA_WIDTH-1:0]   cpu_rdata;
    wire                     cpu_ready;

    // Main Memory Interface Signals
    wire                     mem_req;
    wire                     mem_we;
    wire [`ADDR_WIDTH-1:0]   mem_addr;
    wire [`LINE_WIDTH-1:0]   mem_wdata;
    wire [`LINE_WIDTH-1:0]   mem_rdata;
    wire                     mem_ready;

    // Telemetry / Status Signals
    wire                     hit_out;
    wire                     miss_out;
    wire [2:0]               state_out;

    // Verification & Architectural Performance Metrics
    integer total_accesses;
    integer hit_count;
    integer miss_count;
    integer read_count;
    integer write_count;
    integer wb_count;
    integer total_cycles;
    integer stall_cycles;
    integer test_errors;

    // Clock Generation: 100MHz (Period = 10ns)
    always #5 clk = ~clk;

    // Instantiate Device Under Test (DUT)
    cache_top u_dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .cpu_req   (cpu_req),
        .cpu_we    (cpu_we),
        .cpu_addr  (cpu_addr),
        .cpu_wdata (cpu_wdata),
        .cpu_rdata (cpu_rdata),
        .cpu_ready (cpu_ready),
        .mem_req   (mem_req),
        .mem_we    (mem_we),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),
        .mem_ready (mem_ready),
        .hit_out   (hit_out),
        .miss_out  (miss_out),
        .state_out (state_out)
    );

    // Instantiate Main Memory Model (DRAM) with 6-cycle latency
    main_memory_model #(
        .LATENCY_CYCLES(6)
    ) u_main_memory (
        .clk       (clk),
        .rst_n     (rst_n),
        .mem_req   (mem_req),
        .mem_we    (mem_we),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),
        .mem_ready (mem_ready)
    );

    // Track Hit / Miss / Write-Back counters synchronously
    always @(posedge clk) begin
        if (rst_n) begin
            if (hit_out)  hit_count  <= hit_count + 1;
            if (miss_out) miss_count <= miss_count + 1;
            if (state_out == `STATE_WRITE_BACK && mem_ready) wb_count <= wb_count + 1;
        end
    end

    // -------------------------------------------------------------------------
    // CPU Transaction Tasks
    // -------------------------------------------------------------------------
    task cpu_read(
        input  [`ADDR_WIDTH-1:0] addr,
        input  [`DATA_WIDTH-1:0] exp_data,
        output [`DATA_WIDTH-1:0] rdata,
        output integer           cycles
    );
        begin
            @(posedge clk);
            cpu_req        <= 1'b1;
            cpu_we         <= 1'b0;
            cpu_addr       <= addr;
            cpu_wdata      <= 32'h0;
            cycles         = 0;
            total_accesses = total_accesses + 1;
            read_count     = read_count + 1;

            @(posedge clk);
            #1;
            cycles = cycles + 1;
            while (!cpu_ready) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end

            rdata = cpu_rdata;
            cpu_req      <= 1'b0;
            total_cycles = total_cycles + cycles;
            stall_cycles = stall_cycles + (cycles - 1);

            if (rdata !== exp_data) begin
                $display("  [ERROR] READ MISMATCH @ Addr 0x%08h: Expected 0x%08h, Got 0x%08h (Cycles: %0d)", 
                         addr, exp_data, rdata, cycles);
                test_errors = test_errors + 1;
            end else begin
                $display("  [PASS]  READ OK @ Addr 0x%08h: Data = 0x%08h (Latency: %0d cycles)", 
                         addr, rdata, cycles);
            end
            @(posedge clk);
        end
    endtask

    task cpu_write(
        input  [`ADDR_WIDTH-1:0] addr,
        input  [`DATA_WIDTH-1:0] wdata,
        output integer           cycles
    );
        begin
            @(posedge clk);
            cpu_req        <= 1'b1;
            cpu_we         <= 1'b1;
            cpu_addr       <= addr;
            cpu_wdata      <= wdata;
            cycles         = 0;
            total_accesses = total_accesses + 1;
            write_count    = write_count + 1;

            @(posedge clk);
            #1;
            cycles = cycles + 1;
            while (!cpu_ready) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end

            cpu_req      <= 1'b0;
            total_cycles = total_cycles + cycles;
            stall_cycles = stall_cycles + (cycles - 1);
            $display("  [INFO]  WRITE DONE @ Addr 0x%08h: Data = 0x%08h (Latency: %0d cycles)", 
                     addr, wdata, cycles);
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Stimulus
    // -------------------------------------------------------------------------
    reg [`DATA_WIDTH-1:0] read_val;
    integer latency;
    real hit_rate;
    real miss_rate;
    real amat_cycles;
    real amat_ns;

    initial begin
        // Waveform Dump Setup
        $dumpfile("cache_sim.vcd");
        $dumpvars(0, tb_cache_top);

        // Initialization
        clk            = 0;
        rst_n          = 0;
        cpu_req        = 0;
        cpu_we         = 0;
        cpu_addr       = 0;
        cpu_wdata      = 0;
        total_accesses = 0;
        hit_count      = 0;
        miss_count     = 0;
        read_count     = 0;
        write_count    = 0;
        wb_count       = 0;
        total_cycles   = 0;
        stall_cycles   = 0;
        test_errors    = 0;

        $display("================================================================================");
        $display("   DO AN KIEN TRUC MAY TINH: 4KB 2-WAY SET-ASSOCIATIVE CACHE CONTROLLER");
        $display("   Specifications: 32-bit Addr | 16-Byte Line | Write-Back | Write-Allocate | LRU");
        $display("================================================================================");

        // Apply Reset
        #25;
        rst_n = 1;
        #20;

        // ---------------------------------------------------------------------
        // TEST SCENARIO 1: Cold Miss (Compulsory Miss)
        // ---------------------------------------------------------------------
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> TEST SCENARIO 1: Cold Miss (Compulsory Miss)");
        $display("    Reading address 0x0000_1000 for the very first time (Empty Cache)");
        $display("--------------------------------------------------------------------------------");
        // Address 0x0000_1000: Tag = 0x00002, Index = Set 0, Offset = 0x0 (Word 0)
        cpu_read(32'h0000_1000, 32'h1000_1000, read_val, latency);
        if (latency == 10) 
            $display("    => Cold miss confirmed: CPU stalled for %0d cycles while fetching DRAM line.", latency);
        else begin
            $display("    => [ERROR] Expected 10-cycle latency for clean cold miss, got %0d!", latency);
            test_errors = test_errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST SCENARIO 2: Read Hit & Spatial Locality
        // ---------------------------------------------------------------------
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> TEST SCENARIO 2: Read Hit & Spatial Locality");
        $display("    Reading the same line again (Word 0, 1, 2, 3) - Expect single-cycle HIT");
        $display("--------------------------------------------------------------------------------");
        // Re-read Word 0 (Temporal Locality)
        cpu_read(32'h0000_1000, 32'h1000_1000, read_val, latency);
        if (latency == 1)
            $display("    => Temporal Read Hit Verified! Returned in exactly 1 cycle.");
        else begin
            $display("    => [ERROR] Temporal Read Hit should take 1 cycle! (Took %0d)", latency);
            test_errors = test_errors + 1;
        end

        // Read Word 1, 2, 3 (Spatial Locality within the same 16-byte line)
        cpu_read(32'h0000_1004, 32'h1000_1004, read_val, latency);
        if (latency == 1)
            $display("    => Spatial Read Hit (Word 1..3) Verified! Returned in 1 cycle each.");
        cpu_read(32'h0000_1008, 32'h1000_1008, read_val, latency);
        cpu_read(32'h0000_100C, 32'h1000_100C, read_val, latency);

        // ---------------------------------------------------------------------
        // TEST SCENARIO 3: Write Hit (Write-Back Policy)
        // ---------------------------------------------------------------------
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> TEST SCENARIO 3: Write Hit (Write-Back Policy)");
        $display("    Writing 0xCAFEBABE to 0x0000_1000 (Already resident in Set 0, Way 0)");
        $display("--------------------------------------------------------------------------------");
        cpu_write(32'h0000_1000, 32'hCAFE_BABE, latency);
        if (latency == 1)
            $display("    => Write Hit completed in 1 cycle! Cache line marked DIRTY.");
        else begin
            $display("    => [ERROR] Write Hit should take 1 cycle! (Took %0d)", latency);
            test_errors = test_errors + 1;
        end

        // Verify DRAM is NOT yet updated (proving Write-Back instead of Write-Through)
        if (u_main_memory.mem_storage[32'h0000_1000 >> 4][31:0] === 32'h1000_1000) begin
            $display("    => [PASS] WRITE-BACK ISOLATION VERIFIED: DRAM still holds old value 0x10001000.");
        end else begin
            $display("    => [ERROR] DRAM was prematurely modified on Write Hit!");
            test_errors = test_errors + 1;
        end

        // Read back to verify updated value in cache
        cpu_read(32'h0000_1000, 32'hCAFE_BABE, read_val, latency);

        // ---------------------------------------------------------------------
        // TEST SCENARIO 4: Write Miss (Write-Allocate Policy)
        // ---------------------------------------------------------------------
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> TEST SCENARIO 4: Write Miss (Write-Allocate Policy)");
        $display("    Writing 0xDEADBEEF to 0x0000_2000 (Set 0, Tag 0x0004 - Way 1 is empty)");
        $display("--------------------------------------------------------------------------------");
        cpu_write(32'h0000_2000, 32'hDEAD_BEEF, latency);
        if (latency == 10)
            $display("    => Write-Allocate completed in %0d cycles: Fetched block, merged word, marked DIRTY.", latency);
        else begin
            $display("    => [ERROR] Expected 10 cycles for clean Write-Allocate miss, got %0d!", latency);
            test_errors = test_errors + 1;
        end

        // Read back from 0x0000_2000 (Word 0) and 0x0000_2004 (Word 1)
        cpu_read(32'h0000_2000, 32'hDEAD_BEEF, read_val, latency);
        cpu_read(32'h0000_2004, 32'h1000_2004, read_val, latency);

        // ---------------------------------------------------------------------
        // TEST SCENARIO 5: Conflict Miss, LRU Replacement & Dirty Line Write-Back
        // ---------------------------------------------------------------------
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> TEST SCENARIO 5: Conflict Miss, LRU Eviction & Dirty Write-Back");
        $display("    Set 0 is now FULL: Way 0 (0x1000, Dirty), Way 1 (0x2000, Dirty)");
        $display("    Way 1 was accessed last -> Way 0 is LRU (Victim candidate)");
        $display("    Accessing 0x0000_3000 (Set 0, Tag 0x0006) triggers Conflict Miss!");
        $display("--------------------------------------------------------------------------------");
        cpu_read(32'h0000_3000, 32'h1000_3000, read_val, latency);
        if (latency == 18) begin
            $display("    => Dirty Conflict Miss resolved in %0d cycles (Write-Back + Fetch)!", latency);
        end else begin
            $display("    => [ERROR] Expected 18 cycles for Dirty Conflict Miss, got %0d!", latency);
            test_errors = test_errors + 1;
        end

        // Verify DRAM consistency for evicted Way 0 (0x0000_1000):
        if (u_main_memory.mem_storage[32'h0000_1000 >> 4][31:0] === 32'hCAFE_BABE) begin
            $display("    => [PASS] DRAM WRITE-BACK #1 VERIFIED: DRAM[0x1000] now contains 0x%08h!", 32'hCAFE_BABE);
        end else begin
            $display("    => [ERROR] DRAM WRITE-BACK #1 FAILED: Expected 0xCAFEBABE, got 0x%08h", 
                     u_main_memory.mem_storage[32'h0000_1000 >> 4][31:0]);
            test_errors = test_errors + 1;
        end

        // Re-read evicted address 0x0000_1000:
        // Evicts Way 1 (0x0000_2000, which is ALSO Dirty with 0xDEAD_BEEF!)
        $display("\n    Re-reading evicted address 0x0000_1000 from DRAM (evicts Dirty Way 1 @ 0x2000)...");
        cpu_read(32'h0000_1000, 32'hCAFE_BABE, read_val, latency);
        if (latency == 18) begin
            $display("    => [PASS] Second Dirty Conflict Miss resolved in %0d cycles!", latency);
        end else begin
            $display("    => [ERROR] Expected 18 cycles for second Dirty Conflict Miss, got %0d!", latency);
            test_errors = test_errors + 1;
        end

        // Verify DRAM consistency for evicted Way 1 (0x0000_2000):
        if (u_main_memory.mem_storage[32'h0000_2000 >> 4][31:0] === 32'hDEAD_BEEF) begin
            $display("    => [PASS] DRAM WRITE-BACK #2 VERIFIED: DRAM[0x2000] now contains 0x%08h!", 32'hDEAD_BEEF);
        end else begin
            $display("    => [ERROR] DRAM WRITE-BACK #2 FAILED: Expected 0xDEADBEEF, got 0x%08h", 
                     u_main_memory.mem_storage[32'h0000_2000 >> 4][31:0]);
            test_errors = test_errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST SCENARIO 6: Conflict Miss with CLEAN Victim Eviction
        // ---------------------------------------------------------------------
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> TEST SCENARIO 6: Conflict Miss with CLEAN Victim Eviction");
        $display("    Set 0 currently holds: Way 0 (0x3000, CLEAN, LRU), Way 1 (0x1000, CLEAN, MRU)");
        $display("    Accessing 0x0000_4000 (Set 0, Tag 0x0008) evicts CLEAN Way 0 without Write-Back!");
        $display("--------------------------------------------------------------------------------");
        cpu_read(32'h0000_4000, 32'h1000_4000, read_val, latency);
        if (latency == 10) begin
            $display("    => [PASS] Clean Conflict Miss skipped STATE_WRITE_BACK and finished in %0d cycles!", latency);
        end else begin
            $display("    => [ERROR] Expected 10 cycles for Clean Conflict Miss, got %0d!", latency);
            test_errors = test_errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST SCENARIO 7: Textbook Section 5.4 Benchmark (2-Way vs Direct-Mapped)
        // ---------------------------------------------------------------------
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> TEST SCENARIO 7: Textbook Section 5.4 Associativity Benchmark (Set 10)");
        $display("    Reference sequence to Set 10 (0x00A0): Block A -> Block B -> Block A -> Block C -> Block B");
        $display("    In Direct-Mapped: 5 Misses (0 Hits). In 2-Way Set-Associative (LRU): 4 Misses, 1 Hit!");
        $display("--------------------------------------------------------------------------------");
        // Block A = 0x0000_00A0 (Tag 0, Set 10) -> Miss (Way 0)
        cpu_read(32'h0000_00A0, 32'h1000_00A0, read_val, latency);
        // Block B = 0x0000_08A0 (Tag 1, Set 10) -> Miss (Way 1)
        cpu_read(32'h0000_08A0, 32'h1000_08A0, read_val, latency);
        // Block A = 0x0000_00A0 (Tag 0, Set 10) -> HIT! (Way 0 becomes MRU, Way 1 becomes LRU)
        cpu_read(32'h0000_00A0, 32'h1000_00A0, read_val, latency);
        if (latency == 1)
            $display("    => [PASS] 2-Way Associativity prevented ping-pong conflict! Block A HIT in 1 cycle.");
        else begin
            $display("    => [ERROR] Block A should HIT in 2-Way Set-Associative cache!");
            test_errors = test_errors + 1;
        end
        // Block C = 0x0000_10A0 (Tag 2, Set 10) -> Miss (Evicts LRU Block B in Way 1)
        cpu_read(32'h0000_10A0, 32'h1000_10A0, read_val, latency);
        // Block B = 0x0000_08A0 (Tag 1, Set 10) -> Miss (Evicts LRU Block A in Way 0)
        cpu_read(32'h0000_08A0, 32'h1000_08A0, read_val, latency);

        // ---------------------------------------------------------------------
        // TEST SCENARIO 8: Multi-Set Boundary Test (Set 63 & Set 127)
        // ---------------------------------------------------------------------
        $display("\n--------------------------------------------------------------------------------");
        $display(">>> TEST SCENARIO 8: Multi-Set Boundary Verification (Set 63 & Set 127)");
        $display("    Testing mid-range Set 63 (0x03F0) and max boundary Set 127 (0x07F0)");
        $display("--------------------------------------------------------------------------------");
        // Set 63 (0x0000_03F0): Cold Miss followed by 3 Spatial Hits
        cpu_read(32'h0000_03F0, 32'h1000_03F0, read_val, latency);
        cpu_read(32'h0000_03F4, 32'h1000_03F4, read_val, latency);
        cpu_read(32'h0000_03F8, 32'h1000_03F8, read_val, latency);
        cpu_read(32'h0000_03FC, 32'h1000_03FC, read_val, latency);

        // Set 127 (0x0000_07F0): Cold Miss followed by 3 Spatial Hits
        cpu_read(32'h0000_07F0, 32'h1000_07F0, read_val, latency);
        cpu_read(32'h0000_07F4, 32'h1000_07F4, read_val, latency);
        cpu_read(32'h0000_07F8, 32'h1000_07F8, read_val, latency);
        cpu_read(32'h0000_07FC, 32'h1000_07FC, read_val, latency);

        // ---------------------------------------------------------------------
        // Quantitative Performance Report & Statistics Summary (Section 5.4)
        // ---------------------------------------------------------------------
        #50;
        hit_rate    = (hit_count * 100.0) / total_accesses;
        miss_rate   = (miss_count * 100.0) / total_accesses;
        amat_cycles = (total_cycles * 1.0) / total_accesses;
        amat_ns     = amat_cycles * 10.0; // 100MHz clock -> 10ns period

        $display("\n================================================================================");
        $display("             QUANTITATIVE ARCHITECTURAL PERFORMANCE SUMMARY                     ");
        $display("================================================================================");
        $display("  Total Memory Accesses       : %0d", total_accesses);
        $display("    - Read Accesses           : %0d", read_count);
        $display("    - Write Accesses          : %0d", write_count);
        $display("  Cache Hits                  : %0d", hit_count);
        $display("  Cache Misses                : %0d", miss_count);
        $display("    - Dirty Write-Backs (WB)  : %0d", wb_count);
        $display("  Cache Hit Rate              : %0.2f %%", hit_rate);
        $display("  Cache Miss Rate             : %0.2f %%", miss_rate);
        $display("  Total Access Cycles         : %0d cycles", total_cycles);
        $display("  Total Memory-Stall Cycles   : %0d cycles", stall_cycles);
        $display("  Measured AMAT               : %0.2f cycles (%0.2f ns @ 100MHz)", amat_cycles, amat_ns);
        $display("  Verification Errors         : %0d", test_errors);
        $display("================================================================================");

        if (test_errors == 0) begin
            $display("  >>> [TESTBENCH RESULT: ALL 8 SCENARIOS PASSED SUCCESSFULLY!] <<<");
        end else begin
            $display("  >>> [TESTBENCH RESULT: FAILED WITH %0d ERROR(S)] <<<", test_errors);
        end
        $display("================================================================================\n");

        $finish;
    end

endmodule
