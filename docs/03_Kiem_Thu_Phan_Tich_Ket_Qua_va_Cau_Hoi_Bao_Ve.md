# Tài Liệu 03: Kiểm Thử Mô Phỏng (Verification), Phân Tích Kết Quả & Câu Hỏi Bảo Vệ Đồ Án

> **Tài liệu hướng dẫn kiểm chứng phần cứng, đọc dạng sóng GTKWave (`cache_sim.vcd`) và ngân hàng câu hỏi vấn đáp chuyên sâu**  
> **Liên kết mã nguồn**: [`sim/tb_cache_top.v`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/sim/tb_cache_top.v), [`sim/main_memory_model.v`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/sim/main_memory_model.v), [`scripts/cache_architectural_suite.py`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/scripts/cache_architectural_suite.py).

---

## Mục Lục
1. [Phương pháp Kiểm thử Tự động (Self-Checking Verification Methodology)](#1-phương-pháp-kiểm-thử-tự-động-self-checking-verification-methodology)
2. [Phân tích Chi tiết 8 Kịch bản Kiểm thử trong `tb_cache_top.v`](#2-phân-tích-chi-tiết-8-kịch-bản-kiểm-thử-trong-tb_cache_topv)
3. [Hướng dẫn Phân tích Dạng sóng (Waveform) trên GTKWave](#3-hướng-dẫn-phân-tích-dạng-sóng-waveform-trên-gtkwave)
4. [Bộ 12 Câu hỏi & Trả lời Vấn đáp Bảo vệ Đồ án (Viva / Defense Q&A)](#4-bộ-12-câu-hỏi--trả-lời-vấn-đáp-bảo-vệ-đồ-án-viva--defense-qa)

---

## 1. Phương pháp Kiểm thử Tự động (Self-Checking Verification Methodology)

Môi trường kiểm thử trong [`sim/tb_cache_top.v`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/sim/tb_cache_top.v) được xây dựng theo chuẩn **Self-Checking Testbench** kết hợp với **Golden Reference Model** bằng Python ([`scripts/cache_architectural_suite.py`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/scripts/cache_architectural_suite.py)):
- **Khởi tạo Bộ nhớ DRAM Định trước (Deterministic Pattern)**:
  Tại [`sim/main_memory_model.v`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/sim/main_memory_model.v#L41-L51), mỗi địa chỉ byte căn chỉnh 4-byte `Addr` được khởi tạo giá trị mặc định là `32'h1000_0000 | Addr`. Ví dụ:
  - Dòng `0x0000_1000` chứa 4 từ: `Word 0 = 0x1000_1000`, `Word 1 = 0x1000_1004`, `Word 2 = 0x1000_1008`, `Word 3 = 0x1000_100C`.
  - Quy ước này giúp dễ dàng nhận biết ngay trên dạng sóng xem từ dữ liệu đang đọc thuộc dòng nào và Word thứ mấy.
- **Hai tác vụ giao dịch chuẩn (`cpu_read` và `cpu_write`)**:
  - Phát yêu cầu ở sườn lên xung nhịp, đếm chính xác số chu kỳ `cycles` cho tới khi `cpu_ready == 1`.
  - Tự động đối chiếu `cpu_rdata` với giá trị kỳ vọng `exp_data`; nếu sai lệch lập tức báo `[ERROR]` và tăng biến đếm `test_errors`.
  - Tự động tích lũy `total_cycles`, `stall_cycles = stall_cycles + (cycles - 1)`, `hit_count`, `miss_count`, và `wb_count` (số lần ghi trả dòng bẩn về DRAM).

---

## 2. Phân tích Chi tiết 8 Kịch bản Kiểm thử trong `tb_cache_top.v`

| Kịch bản | Mục tiêu Kiểm chứng Kiến trúc | Địa chỉ & Thao tác | Kết quả Kỳ vọng & Giải thích Vi kiến trúc |
| :--- | :--- | :--- | :--- |
| **Scenario 1: Cold Miss** | Kiểm tra lỗi bắt buộc (Compulsory Miss) khi Cache vừa Reset (`Valid = 0`). | `READ 0x0000_1000` (`Tag = 0x02, Set = 0, Word = 0`) | **Miss (`10 cycles`)**: `lru_logic` thấy `valid0 == 0` nên chọn `Way 0`. FSM nạp dòng `0x1000..0x100C` từ DRAM vào `Set 0, Way 0`, đặt `Valid0 = 1, Dirty0 = 0, LRU[0] = 1` (Way 1 thành LRU). |
| **Scenario 2: Read Hit & Spatial Locality** | Kiểm chứng tính cục bộ thời gian (Temporal) và không gian (Spatial). | `READ 0x1000`, `0x1004`, `0x1008`, `0x100C` (4 Words liên tiếp) | **4 Hits liên tiếp (`1 cycle/read`)**: Nhờ Scenario 1 đã nạp cả dòng 128-bit (16 Bytes), cả 4 lần đọc đều trúng tại `Set 0, Way 0` và trả dữ liệu ngay trong 1 chu kỳ. |
| **Scenario 3: Write Hit (Write-Back)** | Kiểm chứng chính sách Write-Back khi ghi trúng. | `WRITE 0xCAFE_BABE` vào `0x0000_1000`, sau đó `READ 0x0000_1000` | **Write Hit (`1 cycle`) + Read Hit (`1 cycle`)**: Dữ liệu tại `Set 0, Way 0, Word 0` đổi thành `0xCAFE_BABE`, cờ `Dirty0` bật lên `1`. Kiểm tra trực tiếp mảng DRAM xác nhận `DRAM[0x1000]` **vẫn giữ giá trị cũ `0x1000_1000`**. |
| **Scenario 4: Write Miss (Write-Allocate)** | Kiểm chứng chính sách Write-Allocate và ưu tiên cấp phát vào Way trống. | `WRITE 0xDEAD_BEEF` vào `0x0000_2000` (`Tag = 0x04, Set = 0`), đọc lại `0x2000` & `0x2004` | **Write Miss (`10 cycles`) + 2 Read Hits (`1 cycle`)**: Tại `Set 0`, `Way 0` đang hợp lệ nhưng `Way 1` còn trống (`valid1 = 0`) $\to$ Cấp phát vào `Way 1` mà không đụng tới `Way 0`. Nạp dòng `0x2000` từ DRAM, trộn `0xDEAD_BEEF` vào `Word 0`, giữ nguyên `Word 1 = 0x1000_2004`, bật `Dirty1 = 1, LRU[0] = 0` (`Way 0` thành LRU). |
| **Scenario 5: Conflict Miss, LRU Eviction & Dirty Write-Back** | Kiểm chứng xung đột tập hợp, chọn nạn nhân LRU và ghi trả dòng bẩn (`Dirty = 1`) về DRAM. | 1) `READ 0x0000_3000` (`Tag = 0x06, Set = 0`)<br>2) `READ 0x0000_1000` (`Tag = 0x02, Set = 0`) | 1) **Dirty Miss (`18 cycles`)**: `Set 0` đã đầy. Vì `LRU[0] == 0`, `Way 0` (`0x1000`, đang `Dirty0 = 1`) bị chọn làm nạn nhân. FSM vào `STATE_WRITE_BACK` ghi `0xCAFE_BABE` về DRAM (8 chu kỳ), rồi vào `STATE_FETCH_MEM` nạp `0x3000` vào `Way 0` (`Dirty0 = 0, LRU[0] = 1`).<br>2) **Dirty Miss (`18 cycles`)**: Đọc lại `0x1000` gây Miss, trục xuất `Way 1` (`0x2000`, đang `Dirty1 = 1`), ghi trả `0xDEAD_BEEF` về DRAM rồi nạp lại `0x1000` (có chứa `0xCAFE_BABE`) từ DRAM lên `Way 1`! |
| **Scenario 6: Clean Victim Eviction** | Kiểm chứng tối ưu hóa bỏ qua Write-Back khi dòng nạn nhân sạch (`Dirty = 0`). | `READ 0x0000_4000` (`Tag = 0x08, Set = 0`) | **Clean Conflict Miss (`10 cycles`)**: Lúc này tại `Set 0`, `Way 0` đang chứa `0x3000` (`Dirty0 = 0`, sạch, là LRU). Khi truy cập `0x4000`, FSM phát hiện `victim_dirty == 0` nên nhảy thẳng từ `COMPARE_TAG` sang `FETCH_MEM`, chỉ tốn **10 chu kỳ** thay vì 18 chu kỳ! |
| **Scenario 7: Textbook Section 5.4 Benchmark** | Đối chiếu bài tập kinh điển Mục 5.4 (trang 405–406 [`5.3-5.4.pdf`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/5.3-5.4.pdf)) trên `Set 10`. | Chuỗi khối cùng ánh xạ vào `Set 10`: `Block A (0x00A0)` $\to$ `Block B (0x08A0)` $\to$ `Block A (0x00A0)` $\to$ `Block C (0x10A0)` $\to$ `Block B (0x08A0)` | Chuỗi kết quả: **Miss (10c) $\to$ Miss (10c) $\to$ HIT (1c) $\to$ Miss (10c) $\to$ Miss (10c)**. Chứng minh 2-Way Set-Associative giúp lần truy cập thứ 3 (`Block A`) đạt **Hit**, trong khi Direct-Mapped bị trượt cả 5 lần! |
| **Scenario 8: Multi-Set Boundary & AMAT** | Kiểm chứng giải mã chỉ số Set ở vùng giữa (`Set 63`) và biên trên cùng (`Set 127`). | Đọc chuỗi 4 Words tại `0x03F0..0x03FC` (`Set 63`) và `0x07F0..0x07FC` (`Set 127`) | Mỗi Set chịu 1 Cold Miss (`10 cycles`) theo sau bởi 3 Spatial Hits (`1 cycle`), không gây nhiễu sang `Set 0` hay `Set 10`. Tổng hợp toàn bộ 26 truy cập đạt **AMAT = 5.42 cycles**. |

---

## 3. Hướng dẫn Phân tích Dạng sóng (Waveform) trên GTKWave

Sau khi chạy mô phỏng, file dạng sóng [`cache_sim.vcd`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/cache_sim.vcd) được tạo tự động. Khi mở bằng **GTKWave**, hãy thêm các nhóm tín hiệu sau vào cửa sổ quan sát để thuyết trình trước hội đồng:

1. **Nhóm Xung nhịp & Giao diện CPU (`tb_cache_top.u_dut`)**:
   - `clk`, `rst_n`
   - `cpu_req`, `cpu_we`, `cpu_addr[31:0]`, `cpu_wdata[31:0]`, `cpu_rdata[31:0]`, `cpu_ready`
2. **Nhóm Trạng thái FSM & Kết quả Tra cứu (`tb_cache_top.u_dut`)**:
   - `state_out[2:0]` *(Đổi định dạng hiển thị sang Binary hoặc đặt Alias: `0=IDLE, 1=CMP_TAG, 2=WB, 3=FETCH, 4=REFILL`)*
   - `hit_out`, `miss_out`, `hit0`, `hit1`, `victim_way`, `lru_bit`
3. **Nhóm Trạng thái Mảng Tag & Dirty (`tb_cache_top.u_dut`)**:
   - `valid0`, `dirty0`, `tag0[20:0]`
   - `valid1`, `dirty1`, `tag1[20:0]`
4. **Nhóm Giao diện Bộ nhớ DRAM (`tb_cache_top.u_dut`)**:
   - `mem_req`, `mem_we`, `mem_addr[31:0]`, `mem_wdata[127:0]`, `mem_rdata[127:0]`, `mem_ready`

### Các Mốc Thời Gian (Timestamps) Đáng Chú Ý Trên Dạng Sóng `cache_sim.vcd`:
- **`45 ns – 155 ns` (Scenario 1 – Cold Miss)**: Quan sát `state_out` chuyển `0 (IDLE) -> 1 (CMP_TAG) -> 3 (FETCH_MEM) -> 4 (REFILL) -> 0 (IDLE)`. Tín hiệu `miss_out` nháy lên `1` tại `CMP_TAG`, `mem_req` giữ mức `1` cho đến khi `mem_ready` bật lên `1`, sau đó `valid0` chuyển từ `0` lên `1`.
- **`165 ns – 275 ns` (Scenario 2 – 4 Lần Read Hit Liên Tiếp)**: Mỗi lần `cpu_req = 1`, `state_out` chỉ chuyển `0 -> 1 -> 0` trong đúng 1 chu kỳ xung nhịp (`10 ns`), `hit_out = 1` và `cpu_ready = 1` lập tức.
- **`285 ns – 305 ns` (Scenario 3 – Write Hit)**: Tại `state_out == 1`, `cpu_we = 1`, `hit0 = 1`, ngay sườn xung nhịp tiếp theo tín hiệu `dirty0` chuyển từ `0` lên `1` trong khi `mem_req` vẫn nằm im ở `0`.
- **`445 ns – 635 ns` (Scenario 5 – Dirty Conflict Miss có Write-Back)**: Quan sát rõ chuỗi trạng thái đầy đủ 5 bước `0 -> 1 -> 2 (WRITE_BACK) -> 3 (FETCH_MEM) -> 4 (REFILL) -> 0`:
  - Ở trạng thái `2 (WRITE_BACK)`: `mem_we = 1`, `mem_addr = 0x00001000`, `mem_wdata` xuất dòng 128-bit có chứa `0xCAFEBABE` ở 32 bit thấp.
  - Ở trạng thái `3 (FETCH_MEM)`: `mem_we = 0`, `mem_addr = 0x00003000`, tải dòng mới về.

---

## 4. Bộ 12 Câu hỏi & Trả lời Vấn đáp Bảo vệ Đồ án (Viva / Defense Q&A)

Dưới đây là các câu hỏi chuyên sâu mà giảng viên / hội đồng chấm đồ án Kiến trúc máy tính thường hỏi nhất, kèm câu trả lời chuẩn xác dựa trên thiết kế của đồ án:

### Câu 1: Tại sao địa chỉ 32-bit trong đồ án lại được chia thành 21-bit Tag, 7-bit Index, 2-bit Word Select và 2-bit Byte Offset?
- **Trả lời**:
  - Kích thước mỗi dòng Cache là $16\text{ Bytes} = 2^4\text{ Bytes}$, nên cần **4 bit thấp nhất `[3:0]`** làm *Block Offset*. Vì mỗi từ dữ liệu CPU rộng $32\text{ bits} = 4\text{ Bytes}$, cần $\log_2(4) = \mathbf{2\text{ bits}}$ `[1:0]` cho *Byte Offset* và $\log_2(16/4) = \mathbf{2\text{ bits}}$ `[3:2]` cho *Word Select* để chọn 1 trong 4 Words trong dòng.
  - Tổng dung lượng dữ liệu là $4\text{ KB} = 4096\text{ Bytes}$, suy ra tổng số dòng là $4096 / 16 = 256\text{ dòng}$. Do cấu trúc là **2-Way Set-Associative** (mỗi Set chứa 2 dòng), số lượng Set là $256 / 2 = 128 = 2^7\text{ Sets}$. Do đó cần **7 bit `[10:4]`** làm *Set Index*.
  - Số bit còn lại của địa chỉ 32-bit dành cho *Tag* là $32 - 7 - 4 = \mathbf{21\text{ bits}}$ `[31:11]`.

### Câu 2: Tại sao không lưu luôn 7 bit Index vào trong Tag Array mà chỉ lưu 21 bit Tag?
- **Trả lời**: Theo nguyên lý trong giáo trình (Mục 5.3, trang 384 [`5.3-5.4.pdf`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/5.3-5.4.pdf)), bản thân vị trí hàng thứ `i` (`0..127`) trong mảng SRAM đã chính là giá trị của trường `Index` (`7 bits`). Việc lưu lại 7 bit `Index` vào trong bảng Tag là hoàn toàn dư thừa (redundant) và làm lãng phí $256 \times 7 = 1,792\text{ bits}$ bộ nhớ SRAM. Khi cần tái tạo lại địa chỉ vật lý đầy đủ để thực hiện **Write-Back** (như ở dòng 241 của [`rtl/cache_controller.v`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/rtl/cache_controller.v#L241)), bộ điều khiển chỉ cần ghép nối (concatenate) `{latched_victim_tag, latched_addr[10:4], 4'b0000}`.

### Câu 3: Tại sao trong chính sách Write-Back, lệnh Ghi (Store) không thể ghi đè ngay vào Data Array trong cùng lúc đang đọc Tag như ở Direct-Mapped Write-Through?
- **Trả lời**: Theo phân tích tại Mục 5.3 (trang 394–395 [`5.3-5.4.pdf`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/5.3-5.4.pdf)), trong bộ nhớ đệm **Write-Back**, dữ liệu nằm trong Cache có thể là bản cập nhật duy nhất trong toàn hệ thống (`Dirty = 1`, chưa được sao lưu dưới DRAM) và trong cấu trúc **2-Way**, ta cũng chưa biết dữ liệu đang nằm ở `Way 0` hay `Way 1` trước khi so sánh Tag. Nếu ghi đè mù vào Data Array trước khi xác nhận `hit == 1` và xác định đúng `hit_way`, ta sẽ phá hủy dữ liệu của một khối nhớ khác đang nằm ở đó. Vì vậy, trong [`rtl/cache_controller.v`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/rtl/cache_controller.v#L223-L234), tín hiệu `word_we0` hoặc `word_we1` chỉ được bật lên `1` sau khi tổ hợp so sánh Tag khẳng định `hit == 1`, và việc ghi dữ liệu diễn ra an toàn tại sườn lên xung nhịp cuối chu kỳ `STATE_COMPARE_TAG`.

### Câu 4: Khối `lru_logic.v` xử lý như thế nào khi Set vẫn còn dòng trống (`Valid = 0`)? Tại sao không dùng luôn `lru_bit` ngay từ đầu?
- **Trả lời**: Nếu một Set có `Way 0` hợp lệ (`valid0 = 1`) và `Way 1` còn đang trống (`valid1 = 0`), giả sử `lru_bit` đang trỏ vào `Way 0` thì việc dùng mù quáng `lru_bit` sẽ trục xuất oan `Way 0` trong khi `Way 1` đang bỏ không! Do đó, trong [`rtl/lru_logic.v`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/rtl/lru_logic.v#L62-L70), mạch tổ hợp luôn kiểm tra `!valid0` trước, sau đó đến `!valid1`, và chỉ khi **cả hai Way đều đã hợp lệ (`valid0 && valid1`)** thì mới dùng `lru_bit` để chọn đường nạn nhân.

### Câu 5: Tại sao khi xảy ra Write Miss (với chính sách Write-Allocate), bộ điều khiển vẫn phải đọc toàn bộ dòng 128-bit từ DRAM lên rồi mới ghi từ 32-bit của CPU vào?
- **Trả lời**: Bởi vì một dòng Cache rộng **128 bits (4 Words)**, trong khi lệnh ghi của CPU chỉ cung cấp dữ liệu mới cho **1 Word (32 bits)**. Nếu không đọc dòng 128-bit từ DRAM lên trước để lấy giá trị hợp lệ của **3 Words còn lại**, 3 Words đó trong dòng Cache sẽ chứa giá trị rác (không hợp lệ), trong khi cả dòng chỉ có duy nhất 1 bit `Valid` chung! Nhờ mạch `merged_line` trong [`rtl/cache_controller.v`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/rtl/cache_controller.v#L174-L184), 3 Words từ DRAM được ghép chung với 1 Word mới từ CPU (`latched_wdata`) tạo thành dòng 128-bit hoàn chỉnh trước khi nạp vào Data Array.

### Câu 6: Khi nào thì một dòng vừa được nạp vào Cache ở trạng thái `STATE_REFILL_UPDATE` có `Dirty = 0`, và khi nào có `Dirty = 1`?
- **Trả lời**:
  - Nếu nguyên nhân gây Miss là lệnh **Đọc (`latched_we == 0` – Read Miss)**: Dữ liệu nạp vào Cache giống hệt 100% với bản gốc dưới DRAM nên được đánh dấu sạch (`dirty_in = 1'b0`).
  - Nếu nguyên nhân gây Miss là lệnh **Ghi (`latched_we == 1` – Write Miss với Write-Allocate)**: Dòng dữ liệu từ DRAM đã được trộn thêm từ mới `latched_wdata` của CPU trước khi nạp vào Cache (trong khi DRAM chưa có từ mới này), nên bắt buộc phải đánh dấu bẩn ngay lập tức (`dirty_in = 1'b1`).

### Câu 7: Tại sao tại trạng thái `STATE_COMPARE_TAG`, khi phát hiện Miss (`!hit`), bộ điều khiển phải chốt ngay `latched_victim_tag` và `latched_victim_data` vào thanh ghi?
- **Trả lời**: Để đảm bảo tính bền vững dữ liệu trên bus bộ nhớ trong suốt nhiều chu kỳ của trạng thái `STATE_WRITE_BACK` tiếp theo, tránh phụ thuộc vào đường đọc tổ hợp từ SRAM và sẵn sàng cho cả các mở rộng kiến trúc (ví dụ khi thêm *Write-Back Buffer* cho phép nạp dòng mới song song với việc ghi trả dòng cũ như mô tả ở trang 395 [`5.3-5.4.pdf`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/5.3-5.4.pdf)).

### Câu 8: Ý nghĩa của tín hiệu `sel_refill_data` trong `cache_top.v` là gì?
- **Trả lời**: Tại trạng thái `STATE_REFILL_UPDATE`, dữ liệu dòng mới `refill_line` chỉ được ghi vào mảng `data_array` ở **sườn lên xung nhịp cuối chu kỳ** `STATE_REFILL_UPDATE`. Nếu `cpu_rdata` chỉ lấy từ đầu ra của `data_array`, CPU sẽ phải đợi thêm 1 chu kỳ nữa mới đọc được dữ liệu. Nhờ bật `sel_refill_data = 1` trong `STATE_REFILL_UPDATE`, bộ chọn kênh tại [`rtl/cache_top.v`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/rtl/cache_top.v#L109-L120) nối thẳng từ dữ liệu cần đọc từ `refill_line` ra `cpu_rdata` ngay trong chu kỳ `STATE_REFILL_UPDATE`, giúp tiết kiệm 1 chu kỳ trễ cho mọi lần Read Miss!

### Câu 9: Nếu tăng độ kết hợp từ 2-Way lên 4-Way (giữ nguyên dung lượng 4KB và kích thước dòng 16B), các thông số địa chỉ và phần cứng thay đổi như thế nào?
- **Trả lời**:
  - Tổng số dòng vẫn là $256\text{ dòng}$.
  - Số lượng Sets giảm một nửa: $256 / 4 = 64\text{ Sets}$ $\to$ Số bit **Index** giảm 1 bit (còn $\log_2(64) = \mathbf{6\text{ bits}}$ `[9:4]`).
  - Số bit **Tag** tăng thêm 1 bit: $32 - 6 - 4 = \mathbf{22\text{ bits}}$ `[31:10]`.
  - Phần cứng cần **4 mảng Tag Array**, **4 mảng Data Array**, **4 bộ so sánh Tag 22-bit song song**, bộ chọn kênh **4-sang-1**, và mạch LRU phức tạp hơn (ví dụ: Pseudo-LRU dùng cây nhị phân 3 bits/Set hoặc ma trận/counter).

### Câu 10: Tại sao khi tăng kích thước dòng Cache (Block Size) quá lớn so với dung lượng Cache thì tỷ lệ Miss Rate lại tăng ngược trở lại (Hình 5.11, trang 391)?
- **Trả lời**: Hiện tượng này gọi là **Cache Pollution (Ô nhiễm bộ nhớ đệm)**. Khi dung lượng Cache cố định mà kích thước mỗi dòng quá lớn, tổng số dòng trong Cache bị giảm mạnh, dẫn đến sự cạnh tranh gay gắt giữa các khối nhớ (**Conflict Miss** tăng cao). Một dòng lớn bị trục xuất ra khỏi Cache trước khi CPU kịp sử dụng hết các từ bên trong nó, đồng thời **Miss Penalty** (thời gian truyền cả dòng lớn từ DRAM) tăng vọt làm suy giảm nghiêm trọng hiệu năng tổng thể.

### Câu 11: Làm thế nào để tích hợp thêm mã sửa lỗi Hamming SEC/DED (Mục 5.5) vào thiết kế Cache RTL này?
- **Trả lời**:
  - Đối với **Data Array**: Có thể trang bị mạch **Hamming SEC/DED (39, 32)** cho mỗi từ 32-bit (thêm 7 bit ECC: 6 bit Hamming parity + 1 bit overall parity) hoặc **SEC/DED (137, 128)** cho toàn dòng 128-bit (thêm 9 bit ECC: 8 bit Hamming parity + 1 bit overall parity).
  - Đối với **Tag Array**: Có thể thêm 1 bit Parity (Single Error Detection) hoặc 6 bit SEC/DED cho trường Tag 21-bit.
  - Khi đọc Cache, khối **ECC Syndrome Decoder** kiểm tra tổ hợp song song với bộ so sánh Tag: nếu phát hiện lỗi 1 bit sẽ tự động đảo bit sai để sửa ngay trên đường đọc ra `cpu_rdata` mà không làm hỏng dữ liệu.

### Câu 12: Làm thế nào để giảm thêm Miss Penalty cho các lần Dirty Conflict Miss (từ 18 chu kỳ xuống 10 chu kỳ) trong thiết kế phần cứng thực tế?
- **Trả lời**: Theo trang 395 của giáo trình [`5.3-5.4.pdf`](file:///c:/Users/LAM%20QUY%20DO/Downloads/project_KTMT/5.3-5.4.pdf), ta có thể bổ sung một **Bộ đệm Ghi trả (Write-Back Buffer / Victim Buffer)** nằm giữa Cache Controller và DRAM. Khi xảy ra Dirty Miss tại `STATE_COMPARE_TAG`, thay vì phải đợi 8 chu kỳ của `STATE_WRITE_BACK` để ghi dòng bẩn xuống DRAM trước, bộ điều khiển đẩy ngay dòng bẩn (`latched_victim_addr`, `latched_victim_data`) vào `Write-Back Buffer` trong 1 chu kỳ, rồi lập tức chuyển sang `STATE_FETCH_MEM` để lấy dữ liệu mới cho CPU chạy tiếp. Sau khi CPU đã nhận được dữ liệu, `Write-Back Buffer` mới âm thầm ghi dòng bẩn xuống DRAM ở chế độ nền (background)!
