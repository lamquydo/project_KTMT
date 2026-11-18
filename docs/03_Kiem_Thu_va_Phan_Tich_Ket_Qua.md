# Tài Liệu 03: Kiểm Thử Mô Phỏng & Phân Tích Kết Quả Thực Nghiệm

Tài liệu này hướng dẫn cách chạy mô phỏng, giải thích chi tiết cơ chế của testbench tự kiểm tra trong [`sim/`](../sim/), theo dõi trạng thái từng bước của **8 kịch bản kiểm thử**, phân tích bảng số liệu hiệu năng và hướng dẫn đọc dạng sóng trên GTKWave.

---

## Mục Lục
1. [Hướng Dẫn Chạy Mô Phỏng Nhanh](#1-hướng-dẫn-chạy-mô-phỏng-nhanh)
2. [Cách Hoạt Động Của Môi Trường Kiểm Thử (`sim/`)](#2-cách-hoạt-động-của-môi-trường-kiểm-thử-sim)
3. [Theo Dõi Từng Bước 8 Kịch Bản Kiểm Thử](#3-theo-dõi-từng-bước-8-kịch-bản-kiểm-thử)
4. [Phân Tích Bảng Kết Quả Định Lượng](#4-phân-tích-bảng-kết-quả-định-lượng)
5. [Hướng Dẫn Đọc Dạng Sóng Trên GTKWave](#5-hướng-dẫn-đọc-dạng-sóng-trên-gtkwave)

---

## 1. Hướng Dẫn Chạy Mô Phỏng Nhanh

Dự án sử dụng **Icarus Verilog** (`iverilog`, `vvp`) để biên dịch/mô phỏng và **GTKWave** (tùy chọn) để xem dạng sóng.

- **Cách 1 — Dùng script trên Windows (khuyến nghị):**
  ```cmd
  .\scripts\run_sim.bat
  ```
- **Cách 2 — Chạy lệnh thủ công (Windows / Linux / macOS):**
  ```bash
  iverilog -I rtl -o sim/cache_sim.out rtl/cache_top.v rtl/cache_controller.v rtl/tag_array.v rtl/data_array.v rtl/lru_logic.v sim/main_memory_model.v sim/tb_cache_top.v
  vvp sim/cache_sim.out
  ```

Sau khi chạy xong, file dạng sóng `cache_sim.vcd` được tạo ở thư mục gốc của project.

---

## 2. Cách Hoạt Động Của Môi Trường Kiểm Thử (`sim/`)

### 2.1. Mô hình DRAM giả lập ([`sim/main_memory_model.v`](../sim/main_memory_model.v))
- **Dung lượng giả lập:** `16,384` dòng $\times$ `128-bit` (`16 Bytes/dòng`) = `256 KB`. Địa chỉ dòng trích từ `mem_addr[17:4]` *(lưu ý: nếu truy cập địa chỉ $\ge \text{0x0004\_0000}$ thì địa chỉ trong mô hình giả lập sẽ bị quay vòng về vùng `256 KB` này)*.
- **Độ trễ cấu hình:** `LATENCY_CYCLES = 6` (tương ứng `8` chu kỳ một pha trên bus DRAM).
- **Quy luật nạp dữ liệu ban đầu (`initial`):** Mọi Word tại địa chỉ byte `Addr` đều được khởi tạo sẵn giá trị `32'h1000_0000 | Addr`. Ví dụ dòng `0x0000_1000` chứa:
  - `Word 0 (0x1000)` = `0x1000_1000`
  - `Word 1 (0x1004)` = `0x1000_1004`
  - `Word 2 (0x1008)` = `0x1000_1008`
  - `Word 3 (0x100C)` = `0x1000_100C`
  Nhờ quy luật này, nhìn vào giá trị dữ liệu là biết ngay nó thuộc địa chỉ nào, rất dễ kiểm tra lỗi.

### 2.2. Testbench tự kiểm tra ([`sim/tb_cache_top.v`](../sim/tb_cache_top.v))
- Tạo xung clock `100 MHz` (chu kỳ `10 ns`), giữ `rst_n = 0` trong `25 ns` rồi nhả reset, chờ `20 ns` trước khi phát giao dịch đầu tiên.
- Định nghĩa 2 task giao tiếp chuẩn:
  - `cpu_read(addr, exp_data, rdata, cycles)`: Bật `cpu_req = 1, cpu_we = 0`, đếm số chu kỳ `cycles` cho tới khi `cpu_ready == 1`, tự động đối chiếu `cpu_rdata` với `exp_data`. Nếu sai lệch sẽ báo `[ERROR]` và tăng `test_errors`.
  - `cpu_write(addr, wdata, cycles)`: Bật `cpu_req = 1, cpu_we = 1`, gửi `cpu_wdata` và đếm `cycles` đến khi `cpu_ready == 1`.
  *(Lưu ý: Cuối mỗi task đều có `@(posedge clk)` sau khi hạ `cpu_req <= 0`, nên luôn có `1` chu kỳ nghỉ ở `STATE_IDLE` giữa hai giao dịch liên tiếp.)*
- Đồng thời đếm `hit_count`, `miss_count`, `wb_count`, `total_cycles`, `stall_cycles` để xuất báo cáo hiệu năng cuối mô phỏng.

---

## 3. Theo Dõi Từng Bước 8 Kịch Bản Kiểm Thử

### 3.1. Chuỗi Kịch bản 1 $\to$ 6 trên `Set 0`
Bảng dưới đây tóm tắt trạng thái của `Set 0` biến đổi liên tục qua 6 kịch bản đầu tiên để sinh viên theo dõi liền mạch:

| Kịch bản | Lệnh CPU thực hiện | Giải mã (`Tag`, `Word`) | Kết quả & Chu kỳ | `Set 0` sau khi xong (`Way 0` \| `Way 1` \| `LRU[0]`) |
| :--- | :--- | :---: | :---: | :--- |
| **1. Cold Miss** | `READ 0x1000` | `Tag=0x02, W0` | **Miss (`10c`)** | `Way0: 0x1000 (D=0)` \| `Way1: Trống` \| `LRU=1` |
| **2. Spatial Hits** | `READ 0x1000, 1004, 1008, 100C` | `Tag=0x02, W0..W3` | **4 Hits (`1c/lần`)** | `Way0: 0x1000 (D=0)` \| `Way1: Trống` \| `LRU=1` |
| **3. Write Hit (WB)** | `WRITE 0xCAFEBABE -> 0x1000` rồi `READ 0x1000` | `Tag=0x02, W0` | **2 Hits (`1c/lần`)** | `Way0: 0x1000 (D=1)` \| `Way1: Trống` \| `LRU=1` |
| **4. Write Miss (WA)** | `WRITE 0xDEADBEEF -> 0x2000` rồi `READ 0x2000, 2004` | `Tag=0x04, W0..W1` | **Miss (`10c`) + 2 Hits (`1c`)** | `Way0: 0x1000 (D=1)` \| `Way1: 0x2000 (D=1)` \| `LRU=0` |
| **5a. Dirty Conflict #1** | `READ 0x3000` (đuổi `Way 0`) | `Tag=0x06, W0` | **Dirty Miss (`18c`)** | `Way0: 0x3000 (D=0)` \| `Way1: 0x2000 (D=1)` \| `LRU=1` |
| **5b. Dirty Conflict #2** | `READ 0x1000` (đuổi `Way 1`) | `Tag=0x02, W0` | **Dirty Miss (`18c`)** | `Way0: 0x3000 (D=0)` \| `Way1: 0x1000 (D=0)` \| `LRU=0` |
| **6. Clean Conflict** | `READ 0x4000` (đuổi `Way 0` sạch) | `Tag=0x08, W0` | **Clean Miss (`10c`)** | `Way0: 0x4000 (D=0)` \| `Way1: 0x1000 (D=0)` \| `LRU=1` |

#### Giải thích ý nghĩa từng kịch bản 1 $\to$ 6:
1. **Kịch bản 1 (Cold Miss):** Cache vừa reset nên cả 2 Way đều trống (`valid = 0`). `lru_logic` ưu tiên cấp phát vào `Way 0` trước, nạp cả 16 Bytes `0x1000..0x100C` từ DRAM lên trong `10` chu kỳ.
2. **Kịch bản 2 (Read Hit & Spatial Locality):** Đọc lại `0x1000` (cục bộ thời gian) và `0x1004, 0x1008, 0x100C` (cục bộ không gian). Cả 4 Word đều đã có sẵn trong `Way 0` nên trúng ngay trong `1` chu kỳ/lần.
3. **Kịch bản 3 (Write Hit — Write-Back):** Ghi `0xCAFE_BABE` vào `0x1000`. Cache cập nhật ngay trong `1` chu kỳ và bật `Dirty0 = 1`. Testbench kiểm tra thẳng vào mảng `u_main_memory.mem_storage` thấy **DRAM vẫn giữ `0x1000_1000`**, chứng minh dữ liệu chưa bị ghi xuống DRAM (đúng chuẩn Write-Back).
4. **Kịch bản 4 (Write Miss — Write-Allocate):** Ghi `0xDEAD_BEEF` vào `0x2000`. Lúc này `Way 0` đang chứa `0x1000` (`valid0 = 1`), còn `Way 1` trống (`valid1 = 0`), nên `lru_logic` chọn `Way 1` mà không đuổi `Way 0`. Cache đọc dòng `0x2000` từ DRAM, trộn `0xDEAD_BEEF` vào Word 0 (giữ nguyên Word 1 là `0x1000_2004`), bật `Dirty1 = 1` trong `10` chu kỳ. Đọc kiểm chứng cả `0x2000` và `0x2004` đều đúng và Hit `1` chu kỳ.
5. **Kịch bản 5 (Conflict Miss, Thay thế LRU & Dirty Write-Back):**
   - **Bước 5a:** `Set 0` đã đầy và `LRU[0] = 0` trỏ vào `Way 0` (`0x1000`, `Dirty0 = 1`). Khi đọc `0x3000`, FSM phải đi đủ 5 trạng thái (`18` chu kỳ): trước hết vào `STATE_WRITE_BACK` đẩy `0xCAFE_BABE` về `DRAM[0x1000]`, sau đó vào `STATE_FETCH_MEM` đọc `0x3000` lên `Way 0`. Testbench kiểm tra trực tiếp `DRAM[0x1000]` xác nhận đã thành `0xCAFE_BABE`.
   - **Bước 5b:** Đọc lại `0x1000` vừa bị đuổi. Lúc này `LRU[0] = 1` trỏ vào `Way 1` (`0x2000`, `Dirty1 = 1`). FSM ghi trả `0xDEAD_BEEF` về `DRAM[0x2000]`, rồi tải lại `0x1000` (lúc này trên DRAM đã có sẵn `0xCAFE_BABE` từ bước 5a!) lên `Way 1` trong `18` chu kỳ.
6. **Kịch bản 6 (Clean Victim Eviction):** Đọc `0x4000`. Lúc này nạn nhân là `Way 0` (`0x3000`) nhưng dòng này sạch (`Dirty0 = 0`). Do đó `victim_dirty = 0`, FSM nhảy thẳng qua `STATE_WRITE_BACK` sang `STATE_FETCH_MEM` và hoàn tất trong `10` chu kỳ.

### 3.2. Kịch bản 7 — Chứng minh ưu thế 2-Way LRU trên `Set 10`
Truy cập chuỗi 5 khối cùng ánh xạ vào `Set 10`: `Block A (0x00A0)` $\to$ `Block B (0x08A0)` $\to$ `Block A (0x00A0)` $\to$ `Block C (0x10A0)` $\to$ `Block B (0x08A0)`.

| Bước | Địa chỉ | Tag | Trước truy cập (`Way 0` \| `Way 1` \| `LRU`) | Kết quả (Chu kỳ) | Sau truy cập (`Way 0` \| `Way 1` \| `LRU`) |
| :---: | :--- | :---: | :--- | :---: | :--- |
| 1 | `0x00A0` (A) | `0` | Trống \| Trống \| `0` | **Miss (`10c`)** | `A` \| Trống \| `1` |
| 2 | `0x08A0` (B) | `1` | `A` \| Trống \| `1` | **Miss (`10c`)** | `A` \| `B` \| `0` |
| 3 | `0x00A0` (A) | `0` | `A` \| `B` \| `0` | **HIT (`1c`)** | `A` \| `B` \| `1` |
| 4 | `0x10A0` (C) | `2` | `A` \| `B` \| `1` | **Miss (`10c`)** | `A` \| `C` \| `0` |
| 5 | `0x08A0` (B) | `1` | `A` \| `C` \| `0` | **Miss (`10c`)** | `B` \| `C` \| `1` |

Nhờ có 2 Way, bước 3 đọc lại `A` đạt **Hit 1 chu kỳ** (thay vì trượt cả 5 lần như Direct-Mapped).

### 3.3. Kịch bản 8 — Kiểm tra biên giải mã Index (`Set 63` và `Set 127`)
- Đọc 4 Word liên tiếp tại `0x03F0..0x03FC` (`Set 63` — vùng giữa) và 4 Word liên tiếp tại `0x07F0..0x07FC` (`Set 127` — biên trên cùng).
- Mỗi Set đều chịu 1 Cold Miss (`10` chu kỳ) ở Word 0 và 3 Spatial Hits (`1` chu kỳ) ở Word 1..3, khẳng định mạch giải mã 7 bit `index` hoạt động chính xác trên toàn dải `0..127` mà không làm sai lệch dữ liệu ở `Set 0` hay `Set 10`.

---

## 4. Phân Tích Bảng Kết Quả Định Lượng

Kết quả thực tế thu được khi chạy `vvp sim/cache_sim.out`:

```text
================================================================================
             QUANTITATIVE ARCHITECTURAL PERFORMANCE SUMMARY                     
================================================================================
  Total Memory Accesses       : 26
    - Read Accesses           : 24
    - Write Accesses          : 2
  Cache Hits                  : 15
  Cache Misses                : 11
    - Dirty Write-Backs (WB)  : 2
  Cache Hit Rate              : 57.69 %
  Cache Miss Rate             : 42.31 %
  Total Access Cycles         : 141 cycles
  Total Memory-Stall Cycles   : 115 cycles
  Measured AMAT               : 5.42 cycles (54.23 ns @ 100MHz)
  Verification Errors         : 0
================================================================================
  >>> [TESTBENCH RESULT: ALL 8 SCENARIOS PASSED SUCCESSFULLY!] <<<
================================================================================
```

### Kiểm tra lại từng con số để hiểu bản chất:
1. **Tổng số truy cập = `26` (`24` Read + `2` Write):**
   - `15` Hits (`1` chu kỳ/lần): Kịch bản 2 (`4`), Kịch bản 3 (`2`), Kịch bản 4 (`2`), Kịch bản 7 (`1`), Kịch bản 8 (`6`) $\implies 15 \times 1 = 15$ chu kỳ (`0` stall).
   - `9` Clean Misses (`10` chu kỳ/lần): Kịch bản 1 (`1`), Kịch bản 4 (`1`), Kịch bản 6 (`1`), Kịch bản 7 (`4`), Kịch bản 8 (`2`) $\implies 9 \times 10 = 90$ chu kỳ (`81` chu kỳ stall).
   - `2` Dirty Misses (`18` chu kỳ/lần): Kịch bản 5 (`2`) $\implies 2 \times 18 = 36$ chu kỳ (`34` chu kỳ stall).
2. **Tổng chu kỳ:** $15 + 90 + 36 = \mathbf{141\text{ cycles}}$.
3. **Tổng chu kỳ Stall:** $141 - 26 = \mathbf{115\text{ cycles}}$ (`81 + 34 = 115`).
4. **AMAT:** $141 / 26 = \mathbf{5.42\text{ cycles}}$ (`5.423 × 10 ns = 54.23 ns`).
5. **Lỗi kiểm chứng:** `0` (`ALL 8 SCENARIOS PASSED SUCCESSFULLY`).

---

## 5. Hướng Dẫn Đọc Dạng Sóng Trên GTKWave

Mở file dạng sóng sau khi chạy mô phỏng:
```bash
gtkwave cache_sim.vcd
```

### 5.1. Các tín hiệu cần kéo ra từ `tb_cache_top -> u_dut`
- **CPU:** `clk`, `rst_n`, `cpu_req`, `cpu_we`, `cpu_addr[31:0]`, `cpu_wdata[31:0]`, `cpu_rdata[31:0]`, `cpu_ready`
- **FSM & Hit/Miss:** `state_out[2:0]`, `hit_out`, `miss_out`, `hit0`, `hit1`, `victim_way`, `lru_bit`
- **Tag & Cờ:** `valid0`, `dirty0`, `tag0[20:0]`, `valid1`, `dirty1`, `tag1[20:0]`
- **DRAM:** `mem_req`, `mem_we`, `mem_addr[31:0]`, `mem_wdata[127:0]`, `mem_rdata[127:0]`, `mem_ready`

### 5.2. Mẹo nhìn dạng sóng nhận biết ngay tình huống
1. **Nhìn `state_out[2:0]` để phân loại lệnh:**
   - `0 -> 1 -> 0` (chỉ 1 chu kỳ ở mức `1`): **Cache Hit**. Lúc này `hit_out = 1`, `cpu_ready = 1`, `mem_req` giữ im ở `0`. Nếu `cpu_we = 1` (Write Hit), nhìn ngay sườn clock tiếp theo sẽ thấy `dirty0` (hoặc `dirty1`) nhảy từ `0` lên `1`.
   - `0 -> 1 -> 3 -> 4 -> 0`: **Clean Miss (`10` chu kỳ)**. Tại `state_out == 3`, `mem_we = 0` và `mem_req = 1` kéo dài cho tới khi `mem_ready` nháy `1` (ngay lúc `mem_ready = 1`, `mem_req` lập tức tụt về `0`). Tại `state_out == 4`, `cpu_ready = 1` và `cpu_rdata` trả ra đúng giá trị cần đọc.
   - `0 -> 1 -> 2 -> 3 -> 4 -> 0`: **Dirty Miss (`18` chu kỳ)**. Ở pha `state_out == 2`, `mem_we = 1`, `mem_addr` mang địa chỉ dòng nạn nhân cũ và `mem_wdata` chứa dòng 128-bit bẩn (`0xCAFE_BABE` hoặc `0xDEAD_BEEF` ở 32 bit thấp) ghi trả xuống DRAM trước khi chuyển sang `state_out == 3` đọc dòng mới.
