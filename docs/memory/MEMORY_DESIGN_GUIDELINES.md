# Zephyr FPGA Memory 設計準則

> 2026-09-05 current-baseline note：本文件的PS/PL transport partition、mailbox
> ownership與證據分級仍有效；其中v3 parameter image、逐stage LUT與尚未連接PE的
> 實作描述，已由
> [`SEQUENTIAL_V4_PE_MEMORY_CONTRACT.md`](SEQUENTIAL_V4_PE_MEMORY_CONTRACT.md)
> 及[accelerator-top handoff](HANDOFF.md)
> 取代。舊parameter-memory ping-pong研究線已移至
> `archive/parameter_memory_ping_pong/`，不屬production compile。

- 日期：2026-09-01（Asia/Taipei）
- 狀態：production architecture baseline 已定；2026-09-02 已完成第一版 v3 artifacts、
  shared memory-service/cache、LayerNorm mailbox及100 MHz representative RTL OOC；
  global-FSM/top整合、Vivado block design、driver、implementation與板測尚未完成
- 目標：PYNQ-Z1 / XC7Z020 (`xc7z020clg400-1`)
- 基準時脈：100 MHz PL/AXI 起始目標
- 適用範圍：parameter image、DDR 搬移、PL parameter cache、memory service、
  CPU LayerNorm mailbox、external ingress/egress DMA、FSM stage barrier、PS/PL
  buffer ownership，以及驗收證據

本文件是 memory subsystem 的規範與實作關卡。它把 transport ownership 固定為：

```text
Parameters:
PC/host v3 generator
  -> PS DDR parameter image
  -> memory.v custom AXI4 read master (AR/R)
  -> 64-bit parameter BRAM stage/tile cache
  -> memory_service adapter
  -> native 128-bit weight / packed parameter / LUT interfaces
  -> shared PE Array

CPU LayerNorm round trip (does not use DDR controller):
PL fullband projection
  -> 64-byte output slot in 4 KiB dual-port mailbox BRAM
  -> AXI BRAM Controller -> PS M_AXI_GP -> CPU preprocessing/LayerNorm
  -> PS M_AXI_GP -> AXI BRAM Controller
  -> 782-byte normalized-subband input slot + atomic commit
  -> PL frame buffer / shared PE Array

External runtime ingress / egress:
PS DDR fullband-input buffer
  -> Xilinx AXI DMA MM2S
  -> 64-bit AXI4-Stream ingress
  -> PL frame buffers / PE Array

PL final-result buffer / PE Array
  -> 64-bit AXI4-Stream egress
  -> Xilinx AXI DMA S2MM
  -> PS DDR final-result buffer

Control / status:
PYNQ PS -> accelerator 32-bit AXI4-Lite -> top/FSM/memory_service
PYNQ PS -> M_AXI_GP -> AXI BRAM Controller -> mailbox BRAM data window
PYNQ PS -> AXI DMA S_AXI_LITE          -> AXI DMA control/status
```

換句話說，`memory.v` 的 custom AXI read path **只搬 PL 消費的靜態
parameters**；GP-mapped mailbox **只搬 fullband projection 與 PS 產生的 normalized
subband vectors**；Xilinx AXI DMA **只搬外部 fullband ingress 與 final egress**。
三條資料路徑不得同時宣稱同一份資料或同一個 buffer 的 ownership。

## 1. 規範用語與證據等級

本文件中的「必須」是 integration gate；未滿足時不得把下一層結果宣稱為通過。
「建議」是目前 PYNQ-Z1 baseline，可在有量測證據與新 decision 時更換。

所有報告必須標示下列其中一種證據，不得混用：

| 證據 | 能支持的結論 | 不能支持的結論 |
| --- | --- | --- |
| Repository fact | 現有介面、shape、已接受 decision、generated artifact | 新 RTL 功能或效能 |
| Analytical estimate | 容量、理論流量、instance-scaled 粗估 | Vivado inference、timing、RTF |
| RTL/reference/XSim | 指定 testbench 的行為正確 | route、DDR sustained bandwidth、板上 cache coherency |
| OOC synthesis | 指定模塊/configuration 的資源與 timing | 完整 interconnect、congestion、end-to-end RTF |
| Full implementation | 指定完整 design 的 utilization、route 與 timing | 實板 bandwidth、driver latency、功耗或音訊品質 |
| Board measurement | 明確 bitstream/software/輸入條件下的實測 | 未量測 configuration 的結果 |

目前 22/22 XSim、real-blob host regression，以及各別 FSM/PE OOC 只支持其
各自 checkpoint；它們不證明 production memory service、AXI BRAM Controller/
mailbox、AXI DMA block design、CDC、GP transaction latency、DDR 競爭或板上 RTF。

## 2. 固定分工與資料分類

| 資料類別 | Source of truth | 搬移路徑 | PL 落點／消費者 |
| --- | --- | --- | --- |
| 原始模型參數 | `upstream/parameters/parameters.bin` 與 manifest | 不直接送 PL | host generator input；不可覆寫 |
| PL 靜態參數 | host 離線產生的 versioned `parameters_v3.bin` | PS DDR -> custom AXI read | parameter stage/tile cache -> `memory_service` |
| PS LayerNorm 參數 | PS software 使用的 float affine/scale data | PS DDR/CPU local | 不進 `memory.v`、不占 PL parameter cache |
| External fullband input | host/PS 產生的 normalized INT8 frame | PS DDR -> AXI DMA MM2S -> AXI4-Stream | PL ingress/frame buffer |
| Fullband projection intermediate | PL fullband projection | PL -> mailbox output slot -> GP MMIO read | PS CPU preprocessing/LayerNorm；不進DDR |
| Normalized subband input | PS CPU preprocessing output | GP MMIO write -> mailbox input slot -> atomic commit | PL subband frame buffer；不進DDR |
| Final/DeepFilter result | PL output | AXI4-Stream -> AXI DMA S2MM -> PS DDR | PS/host 後處理或 ISTFT |
| Recurrent/activation state | 執行中的 PL state owner | native local storage | 不因「parameter」名稱而放入 DDR loader |

`parameters_v3.bin` 的範圍必須只包含 PL 實際消費的靜態資料，例如 weights、
bias、requant multiplier/shift、sigmoid LUT，以及由 PL 執行算子所需的其他固定係數。
沒有 PL runtime port 的 calibration metadata 留在 layout/provenance，不應浪費 BRAM。

### 2.1 模塊責任

- **PC/host generator**：保留 raw source，產生可重建的 v3 binary、layout、RTL
  header、golden 與 SHA；不把 transpose/range truncation 留給 PL。
- **PYNQ PS**：配置互不重疊的 parameter 與 external-DMA DDR regions，驗證 image
  version/hash；以 device/uncached mapping 存取 mailbox、執行 MMIO ordering barrier、
  slot commit/release、preprocessing；並負責必要的 DDR cache maintenance、DMA
  setup（SG mode時才含 descriptor）與錯誤恢復。
- **`memory.v`**：將指定 byte range 由 DDR 搬入 raw 64-bit cache，檢查 AXI read
  response；不理解 tensor、row tile 或 PE response 格式。
- **`memory_service`**：擁有 stage table、bank tag、logical-to-physical address、
  64-to-128-bit assembly、parameter unpack、LUT load，以及 native ready/valid。
- **LayerNorm mailbox**：以 AXI BRAM Controller 將一個獨立 4 KiB dual-port BRAM
  data window映射給PS；PL端控制slot ownership、frame ID、commit/release與atomic valid。
- **Xilinx AXI DMA**：只搬 external fullband ingress/final egress；第一版不搬
  LayerNorm intermediate，也不載入 parameter cache。
- **Global FSM**：提出 stage request、等待 ready/done、處理 timeout/error；未收到
  stage-ready 前不得啟動 compute；fullband output slot尚未交給PS或normalized
  subband input slot尚未atomic commit時，不得越過 `FB_SEND`/`WAIT_PS`。
- **PE/GSU/projection/DeepFilter**：只看 native request/response，不直接實作 AXI。
- **Accelerator AXI4-Lite**：只搬 top/FSM/memory-service/mailbox control/status；
  不得搬 bulk tensor bytes。Mailbox payload使用獨立GP memory-mapped BRAM window；
  AXI4-Lite也不取代 AXI DMA 自己的 `S_AXI_LITE` register interface。

任何新模塊若同時接管上述兩個角色，必須先更新 decision、ownership 與 Gate A，
不能以暫時接線形成第二個 source of truth。

## 3. v3 Parameter Image ABI

### 3.1 必要產物

同一次 generator run 必須原子產生並以同一 image version 綁定：

1. `parameters_v3.bin`；
2. machine-readable layout JSON；
3. RTL offset/shape/header；
4. source manifest/blob SHA 與 output image SHA；
5. dense-reference 逐值 golden report；
6. generator command/version 與 deterministic regeneration test。

binary、JSON、header 與 SHA 不同版時整組失效。PS 必須先驗證 image metadata，
再把 image buffer ownership 交給 PL parameter loader。

### 3.2 固定 encoding

- Endianness 固定為 little-endian；lane 0 位於最低位址 byte。
- Stage 起始位址至少 64-byte aligned；每個 section 的 alignment、byte count、
  padding 與 checksum 必須寫入 layout。
- INT8 weight 的 physical order 固定為：

  ```text
  {operator, matrix, source_index, row_tile, lane}

  row_tiles = ceil(output_rows / 16)
  weight_word_index = matrix_base
                    + source_index * row_tiles
                    + row_tile
  ```

- 每個 weight word 是 16 個 signed INT8／128 bits；partial final tile 的無效 lane
  填 0。64-bit raw cache 以相鄰 lower/upper words 組成一筆 128-bit response。
- Logical request 維持 `{operator/layer, matrix, source_index, row_tile}`，不得因
  backend 改成 linear-only blob 而失去 selected-source addressability。
- Shared GSU 只能刪除已逐 byte 證明相同的 gate weight/weight-scale half；bias、
  gate scale 與 requant records 仍保持各自語意。
- INT64 multiplier/shift 必須在 generator 做明確的 signed 32-bit／6-bit（或介面
  最終凍結的寬度）range check；越界時 generation fail，禁止在 RTL 靜默截位。
- GSU/projection parameter tile 必須按 consumer response 順序預先 pack；LUT 必須有
  獨立 section、長度與完成標記，不能混進每一筆 parameter response。

完整 stage preload 只改變資料排列，不會因 activation sparsity 減少 DDR bytes。
source-major layout 是未來 active-source burst/prefetch 的必要條件，但不是已量測的
DDR bandwidth 改善。

## 4. Parameter Loader、Cache 與 Native Service

### 4.1 Custom AXI read baseline

`rtl/memory/memory.v` 作為 parameter loader，第一版遵守：

- 只使用 AXI4 memory-mapped AR/R；沒有 AW/W/B，也不提供 BRAM-to-DDR writeback。
- Current core baseline 是 32-bit address、64-bit data、INCR burst、one outstanding；
  burst 不跨 4 KiB boundary。
- Command source 必須由 `PARAM_BASE + stage_offset` 算出，destination、byte count
  必須是 8-byte aligned 且不得超過 cache depth。
- `stage_id/stage_bank` 只能透過已驗證的 v3 stage table 轉成
  `cmd_src_addr/cmd_dst_word_addr/cmd_byte_count`；PS 不直接提供未檢查的任意 copy。
- `stage_req_valid` 必須保持到 `stage_req_ready`；成功完成後才可產生
  `stage_load_done`，任何 command/AXI/timeout 錯誤產生 `stage_load_error`。
- Top/block design 必須明定 `ARID/PROT/CACHE/QOS/LOCK`、HP port、response ID、
  address width conversion 與 interconnect 設定；不得依模擬中未連接的 sideband
  推定硬體行為。

### 4.2 Cache baseline 與 ownership

第一個 correctness baseline 建議為 **256 KiB、64-bit、single-stage cache**：

- 以 64-bit BRAM36 mapping 的結構估算約 64/140 BRAM36；這是分析估算，不是
  Vivado utilization。
- v2 最大 stage 為 260,120 bytes，只剩 2,024 bytes margin；v3 真實 stage size、
  padding、banking 與 inference 未通過前，256 KiB 仍是 provisional baseline。
- 預設 512 KiB cache 的結構估算約 128/140 BRAM36，超過 80% high-risk 線；不得
  因「容量放得下」就宣稱適合 PYNQ-Z1。
- 預設是一組 shared PE/memory service，依 stage time-multiplex。三套 subband
  engine/cache 在完整 instance-scaled resource、ports、implementation 與板測通過前
  必須保持關閉。
- 4 KiB LayerNorm mailbox是另一個獨立BRAM，不得從parameter cache位址空間切出，
  也不得由parameter loader覆寫。以`1024 x 32-bit`結構粗估約1個BRAM36；實際
  asymmetric dual-port mapping、AXI BRAM Controller資源與timing仍需OOC/full synthesis。

每個 cache bank 至少有 `{image_version, stage_id, bank_id, valid}` tag，並遵守：

| State | Owner | 允許操作 | 轉移條件 |
| --- | --- | --- | --- |
| `INVALID` | none | 不得 compute | reset、error，或新 load 開始 |
| `LOADING` | parameter loader | loader write；compute 禁止讀此 bank | 完整 load 且無 error |
| `READY` | compute/memory service | native reads；loader 禁止覆寫 | stage 結束並明確 release |
| `ERROR` | recovery logic | 不得讀或啟動 compute | clear/abort 完成後回 `INVALID` |

單 bank baseline 將 load 與 compute 序列化。若改成 ping-pong，兩個 bank 仍各自只有
一個 owner；不得在同 cycle 對同址 word 進行未定義的 loader/compute 存取。任何
partial load、reset、timeout 或 AXI error 都必須清除目的 bank 的 valid tag。

### 4.3 `memory_service` native contract

- Weight response：目前 16-lane consumer 為 128 bits；兩次 64-bit read 的順序、
  latency 與 request tag 必須固定。
- Parameter response：依目前 16-lane fullband interface 組成 GSU 5,792-bit 或
  projection 1,120-bit response；若介面寬度改變，generator ABI 與 TB 必須同版更新。
- LUT：在 operator start 前完成 load/config，並有明確 `lut_ready`；不得與第一筆
  compute request 競賽。
- Ready/valid：request 只在 `valid && ready` 接受；response stall 時 `valid` 與 data
  必須保持穩定，直到 consumer 接受。
- Invalid request：非法 image version、stage、matrix、source、tile 或 out-of-range
  address 必須回報錯誤，不得 wrap 或讀舊 bank。Final partial tile 的 padding 由
  generator驗證為0，consumer依有效lane count mask，不存在獨立lane request。
- Arbitration：shared baseline 一次只有目前 active stage 的 requester；若增加多
  client，必須定義 fairness、response tag 與最壞 latency，並重跑 Gate A/B。

## 5. CPU LayerNorm Mailbox 與 External AXI4-Stream ABI

### 5.1 GP-mapped LayerNorm mailbox

Fullband projection到PS preprocessing，再由PS送回normalized subband vectors的路徑
固定使用一個**獨立4 KiB dual-port mailbox BRAM**。CPU經PS `M_AXI_GP`、PL AXI
interconnect與AXI BRAM Controller存取Port A；PL frame-buffer/mailbox logic使用Port B。
此路徑不配置DDR buffer、不經DDR controller，也不使用AXI DMA。

`MAILBOX_BASE`的系統實體位址在Gate 10由Vivado address map指定；相對offset固定為：

| Region | Offset | 有效payload | 配置空間 | Owner direction |
| --- | ---: | ---: | ---: | --- |
| `FB_OUT_SLOT0` | `0x000` | 64 bytes | 64 bytes | PL -> PS |
| `FB_OUT_SLOT1` | `0x040` | 64 bytes | 64 bytes | PL -> PS |
| reserved | `0x080` | none | 896 bytes | none |
| `SB_IN_SLOT0` | `0x400` | 782 bytes | 1,024 bytes | PS -> PL |
| `SB_IN_SLOT1` | `0x800` | 782 bytes | 1,024 bytes | PS -> PL |
| reserved | `0xC00` | none | 1,024 bytes | none |

Mailbox encoding固定為little-endian、最低位址byte是logical element 0。每個
`SB_IN_SLOT`的782 bytes依下列順序線性排列：

```text
SB0 context 0..3, each 46 INT8
SB1 context 0..2, each 94 INT8
SB2 context 0..1, each 158 INT8
```

CPU/PL若以32/64-bit word搬移，782-byte payload後補2個zero bytes成784 bytes；
其餘slot padding不得被consumer解讀為模型輸入。Fullband output只有在64 bytes全部
寫完後才能publish；subband input只有在782 bytes、zero padding與frame metadata
全部完成後，才能以單一`sb_commit`讓PL看見。

每個direction的兩個slot各自帶`{slot_id, frame_id, state}`，控制/status register
至少提供output ready/release、input commit/release、expected/observed frame ID、
timeout與sticky first fault。Payload不得放進這些AXI4-Lite registers。CPU必須把
mailbox data window映射成device/uncached memory，資料存取完成後執行適用的MMIO/
memory barrier，再寫commit/release。Mailbox不需要DDR cache flush/invalidate。

同一slot禁止interleave frames。Ping-pong只允許不同slot由不同frame持有；任何
duplicate/stale frame ID、錯誤owner、未release就覆寫、reset/abort或timeout，都必須
使受影響slot失效且不得產生`ps_subbands_valid`。第一版讓AXI BRAM Controller、
mailbox Port B、FSM與compute共用100 MHz PL clock；若改成不同clock須另加CDC。

### 5.2 External ingress／egress AXI4-Stream

64-bit AXI4-Stream與Xilinx AXI DMA仍保留給DDR-backed的外部邊界，不承載上述
LayerNorm round trip。Byte依低位lane起遞增，`TKEEP`標示有效bytes，`TLAST`結束
logical packet；source可停頓，sink backpressure時`TDATA/TKEEP/TLAST`必須保持穩定。

| 方向 | Logical payload | 已固定／待定 boundary |
| --- | --- | --- |
| PS DDR -> PL | fullband normalized input | 1 packet，64 個 INT8／64 bytes |
| PL -> PS DDR | final/DeepFilter result | element format、長度與`TLAST` boundary仍待Gate 10凍結 |

現有AXIS adapters沒有用`TID/TDEST/TUSER`。Gate 10必須固定external frame ordering、
final-result format/length與DMA simple/SG mode。Fullband projection與782-byte
subband vectors沒有`TKEEP/TLAST` packet ABI；它們只遵守本節mailbox layout與commit。

## 6. DDR／Mailbox Buffer Ownership 與 Ordering

Parameter image、external MM2S fullband-input buffer與external S2MM final-result
buffer的physical DDR ranges必須互不重疊，alignment、size與owner必須出現在PS
transfer configuration/log中。

- **Parameter DDR**：PS建立/驗證image並完成flush/barrier後，才交給custom master
  read；load期間PS不得改寫該image/version。
- **External input MM2S**：CPU填滿slot並flush後交給DMA；DMA完成前CPU不得重用，
  PL接收完整packet後才釋放frame buffer。
- **External result S2MM**：DMA擁有DDR slot直到completion；CPU在invalidate後才能
  讀取，讀完才歸還free list。
- **External DMA ping-pong/ring（若Gate 10選用）**：每個slot必須有`FREE ->
  PRODUCER_FILL -> READY -> DMA -> CONSUMER -> FREE`的單一owner狀態；slot或
  descriptor reuse必須晚於completion/IRQ。Simple與SG mode不得混寫成同一套ABI。
- 若平台提供coherent allocation，也必須在driver記錄實際port/API與coherency
  保證；不能只因使用PYNQ buffer就省略DDR flush/invalidate驗收。

LayerNorm mailbox不屬DDR allocation，也不得建立同內容的shadow DDR source of truth。
兩個方向的owner狀態固定為：

```text
FB output: FREE -> PL_FILL -> READY_FOR_PS -> FREE  (PS release)
SB input:  FREE -> PS_FILL -> COMMITTED    -> FREE  (PL release)
```

State/commit/release是control-plane事件，BRAM內容本身不是valid標記。Reset、abort、
frame sequence error或任一方中途失敗時，partial slot回`FREE/INVALID`，舊內容不可被
重新解讀。Port A/Port B同時存取僅允許在ownership已證明互不衝突的region/slot；
不依賴同址read-during-write的vendor-specific結果。

Mailbox繞過DDR，因此parameter loader不會與LayerNorm round trip競爭DDR controller。
Custom parameter master與external AXI DMA仍可能在PS DDR競爭；HP port、是否允許
重疊、QoS與arbitration在Gate 10決定。Correctness baseline不要求兩者並行；若啟用
並行，必須用parameter-load + external MM2S/S2MM壓力測試證明無starvation。

## 7. Clock、Reset、Control 與 Error Contract

### 7.1 Clock／CDC

- 第一版讓 custom AXI、parameter cache、`memory_service`、FSM 與 compute 共用
  100 MHz PL clock。
- 第一版也讓AXI BRAM Controller、mailbox BRAM Port B與mailbox ownership logic使用
  同一個100 MHz PL clock；PS CPU透過同步AXI transaction存取，不把CPU clock直接接入
  BRAM第二個clock port。
- External AXI DMA stream或任一consumer若使用不同clock，必須放AXIS Clock
  Converter、async FIFO或經驗證的handshake CDC；禁止直接跨domain接ready/valid。
- 現有 `memory.v` 是 single-clock，不能把兩個 port 直接當成 asynchronous
  dual-clock BRAM；LayerNorm mailbox是另一個明確配置的dual-port memory instance。
- CDC/reset report必須涵蓋data、commit/release pulse、slot/frame status、interrupt，
  以及Gate 10所選external DMA mode需要的multi-bit control structures。

### 7.2 Reset

- 外部 reset 可非同步 assert，但每一 domain 必須同步 deassert；active-low
  `aresetn/rst_n` 與 legacy active-high `rst` 只在 top reset wrapper 轉換。
- Reset順序至少涵蓋PS fabric/interconnect、AXI BRAM Controller/mailbox ownership、
  external DMA/AXIS buffers、parameter loader、cache tags、memory service、FSM與compute。
- Mid-burst/mid-packet/mid-mailbox-fill reset必須invalidate partial cache bank、external
  frame與mailbox slot，清除pending response/commit；reset release後從
  `IDLE`/`INVALID`重啟，不能沿用舊`ready`或舊BRAM內容。

### 7.3 Control-plane semantic ABI

Accelerator AXI4-Lite的正式address map可在Gate 10固定，但至少必須提供：

- start、abort、soft reset、clear error、IRQ mask/ack；
- `PARAM_BASE`、image version、stage/bank command 與 timeout；
- mailbox slot state、frame ID、output ready/release、input commit/release與timeout；
- external frame/packet lengths與sequence policy；
- stage/cache/mailbox/FSM busy/ready/done，以及選擇性同步進來的DMA summary；
- sticky first-fault code、detail address/stage、cycle/byte/burst counters。

多word address/config必須先寫shadow registers，再以單一commit/start原子生效；
不能在只更新一半時被硬體取用。AXI4-Lite不接受bulk parameter或feature payload；
4 KiB mailbox payload只經獨立GP memory-mapped AXI BRAM data window。

Xilinx AXI DMA使用自己的`S_AXI_LITE`control/status。Gate 10必須選擇simple或
scatter-gather mode；若是SG，descriptor位於DDR且由DMA/driver contract管理。不得把
DMA完整register file或未選定的descriptor ring默認成accelerator AXI4-Lite的一部分。

### 7.4 Error 與恢復

PL first fault必須sticky到software ack；PS preflight、mailbox driver與external DMA
driver錯誤也必須寫入同一frame的software log。錯誤分類至少區分：

1. parameter command alignment/range/cache overflow；
2. AXI `SLVERR/DECERR`、early/missing `RLAST`、response ID 或 timeout；
3. PL可檢查的image version/header ID或stage-table bounds mismatch；
4. PS preflight發現image SHA/layout不符並拒絕start；
5. mailbox stale/duplicate frame ID、錯誤slot owner、commit/release順序、overwrite或
   PS round-trip timeout；
6. external AXIS invalid/zero `TKEEP`、unexpected `TLAST`、packet length/order；
7. external AXI DMA error IRQ、依所選mode發生的descriptor/buffer overrun/underrun；
8. LUT not-ready、illegal native request、compute/FSM timeout。

恢復順序固定為：停止發新request -> drain/停止external DMA與custom read ->
invalidate partial bank/external frame/mailbox slot -> latch first fault與context ->
回FSM sticky `ERROR` -> software ack/clear -> 回`IDLE`。錯誤stage、partial external
frame或未commit mailbox frame絕對不得啟動compute。

## 8. PYNQ-Z1 Feasibility Gate

任何 memory/cache/AXI topology 在 substantial RTL implementation 前必須完成
[PYNQ-Z1 feasibility checklist](../PYNQ_Z1_FEASIBILITY_CHECKLIST.md) 的 Gate A：

- intended instance count、lane count與 shared/time-multiplex schedule；
- LUT/FF/DSP/BRAM（含AXI BRAM Controller、mailbox、DMA/interconnect/FIFO/CDC/
  cache/tag）scaled estimate；
- parameter cache/mailbox bytes、BRAM width/depth/banks/ports、DDR regions與同時client；
- 每stage/frame的DDR bytes、GP MMIO reads/writes、burst/packet count、cycles/II、
  PS LayerNorm round-trip與RTF；
- clock/domain/reset/CDC、hotspot、fallback、evidence level與 risk status。

任一單項資源預估超過 PYNQ-Z1 可用量的 80% 必須標 high risk，並提出較小
cache/tile、較少 lanes、較少 parallel instances 或 time-multiplex fallback。代表性
cache、wide adapter、multi-lane/AXI block 必須做 `xc7z020clg400-1` OOC；完整設計仍需
implementation 與板測，不能用單 lane 或單模塊結果外推。

## 9. 十二個實作與驗收關卡

順序按 dependency 固定。Gate 1--3 是 **P0 contract/feasibility**，Gate 4--8 是
**P1 correctness/integration**，Gate 9--12 是 **P2 optimization/system/board**。
任一 gate 未通過，不得用後一 gate 的局部結果跳過 blocker。

1. **固定 transport、parameter／mailbox address語意與ownership（P0）**

   - 前置：讀取現有 AXI、PS/PL、FSM、weight-layout 與 feasibility decisions。
   - 產物：本dataflow、資料分類、parameter region/cache ownership、4 KiB mailbox
     layout/slot contract、100 MHz/CDC/reset/error baseline、register語意與256 KiB
     fallback；列出Gate 10仍需決定的external final-result shape與DMA mode。
   - 驗收：parameter、LayerNorm mailbox與external DMA沒有重疊責任；每個DDR/cache/
     mailbox slot同時只有一個owner；舊AXIS runtime baseline的partial supersession已記錄。
   - Block：parameter/mailbox address、owner、commit、reset/error若仍靠口頭假設，
     不得開始v3、memory-service或mailbox implementation。External final-result待定項
     不阻擋Gate 2--8，但必須在Gate 10凍結。

2. **完成 v3 image generator 與 reproducible artifacts（P0）**

   - 前置：raw blob/manifest 與本 ABI 固定。
   - 產物：`parameters_v3.bin`、layout JSON、RTL header、SHA、golden report，包含
     source-major transpose、lane/padding、parameter lowering與 LUT sections。
   - 驗收：逐值等於 dense reference；shared-gate去重有 byte proof；32/6-bit
     越界時生成失敗；同一 inputs 可 deterministic rebuild 並 `cmp` 全部產物。
   - Block：v2 row-major snapshot或只有 logical sparse test，不能進入 production
     address adapter。

3. **完成 PYNQ-Z1 Gate A（P0）**

   - 前置：v3 真實各 stage bytes、instance/lane count與 stage schedule 已知。
   - 產物：intended-count resource、parameter-cache/mailbox ports與banking、DDR
     bytes/bursts、GP MMIO transaction count、cycles/II、clock/CDC、risk、hotspot與
     fallback表。
   - 驗收：沒有用 single-lane/OOC shell外推完整 fit；超過80%的項目標 high risk；
     256 KiB 若裝不下真實 v3 stage必須在 RTL 前改 tile/fallback。
   - Block：沒有完整 scaled estimate，不得 substantial implementation。

4. **實作並測試PL local memory services（P1）**

   - 前置：v3 ABI、native consumer ports與第5節mailbox ABI frozen，Gate A可行。
   - 產物A：`memory_service`的stage/address translation、2x64->128 weight assembly、
     GSU/projection parameter unpack、LUT load、ready/valid、tag與error handling。
   - 產物B：dual-slot mailbox/frame-buffer logic、Port-B access、frame ID、output
     publish/release、input commit/release、atomic `ps_subbands_valid`與error handling；
     AXI BRAM Controller可在TB先以memory-mapped bus model替代。
   - 驗收：兩組self-checking TB覆蓋正常/邊界、random stall、response hold、reset、
     illegal parameter request，以及partial/stale/duplicate/overwrite/timeout mailbox
     cases；parameter逐值bit-exact，mailbox 64/782-byte順序與padding bit-exact。
   - Block：raw 64-bit BRAM read不能冒充完整parameter service；普通array加ready flag
     也不能冒充具ownership與atomic commit的CPU mailbox。

5. **代表性 OOC synthesis（P1）**

   - 前置：memory-service/mailbox TB pass，cache、mailbox與bank count固定。
   - 產物：`xc7z020clg400-1` 100 MHz OOC utilization/timing、parameter BRAM與mailbox
     dual-port BRAM inference、AXI BRAM Controller/interconnect cost、wide response/
     fanout與unconstrained-path report。
   - 驗收：actual LUT/FF/DSP/BRAM/WNS 有紀錄並標 OOC；不合 Gate B 時先縮
     cache/banking/lanes後重跑，不直接進 full integration。
   - Block：本memory guideline比通用checklist更嚴格，Gate 5 acceptance必須有Vivado
     representative OOC。若本機沒有Vivado，應在可用的Windows/remote環境執行；在
     此之前狀態維持UNKNOWN。後續RTL可平行開發，但Gate 6/7不得標為accepted，且
     不得進Gate 10或宣稱board-ready。

6. **把 parameter barrier與LayerNorm mailbox接入global FSM/controller（P1）**

   - 前置：stage service與mailbox handshake皆已通過獨立測試。
   - 產物：GSU1/GSU2/projection的`stage_req_valid/stage_req_ready`（只代表接受
     request）、`stage_load_done/stage_ready_for_compute/stage_load_error`、LUT-ready、
     bank release，以及`FB_SEND` output publish/release、`WAIT_PS` input commit、
     frame ID、abort/timeout/reset與collision protection。
   - 驗收：只有`stage_ready_for_compute`可解除barrier；load完成前compute不啟動；
     錯誤/timeout進 sticky error；任何時刻不會
     loader寫入active compute bank；只有完整committed mailbox input可解除`WAIT_PS`；
     shared single-PE mode為預設。
   - Block：controller若仍直接從上一operator跳到下一operator，或用未受ownership
     保護的一拍`ps_subbands_valid`取代mailbox commit，不得宣稱整合完成。

7. **Reduced-dimension connected integration TB（P1）**

   - 前置：`memory.v`、adapter、mailbox與FSM/fullband controller可實際連接；
     fullband input/result的64-byte logical boundary已知。
   - 產物：`memory.v + memory_service + mailbox + FSM/fullband controller + fullband
     engines` self-checking TB；以PS mailbox model讀64 bytes、產生reference preprocessing
     並寫/commit 782 bytes。External AXIS只需提供fullband ingress必要刺激。
   - 驗收：stage reload、DDR/BRAM stalls、native backpressure、reset/clear、錯誤注入與
     mailbox stalls/partial commit/frame mismatch、multi-frame recurrent state都等於
     reference。Final/DeepFilter external packet不屬本gate blocker。
   - Block：僅把獨立 TB 全部跑過，不算 connected integration。

8. **Full-size real-v3-image simulation（P1）**

   - 前置：reduced integration PASS，v3 artifacts frozen。
   - 產物：真實64->320->320->64 regression、PS preprocessing/normalized inputs與
     golden outputs、physical read log、DDR burst/byte、mailbox Port-B/MMIO transaction
     model與cycle counters。
   - 驗收：逐值 bit-exact；記錄 stage-load、weight/parameter/LUT latency、cycles/frame、
     burst count、mailbox ownership/frame order及multi-frame state；結果明標simulation
     而非CPU/board performance。
   - Block：synthetic小尺寸或 host-only sparse讀取不能替代 full-size connected sim。

9. **只依量測瓶頸做 cache／fetch 優化（P2）**

   - 前置：Gate 8 提供可量化瓶頸，Gate 5提供實際 resource/timing。
   - 產物：256 KiB single-stage、active-source fetch、source-row prefetch、tile
     ping-pong比較；必要時評估 multi-bit spike indexer。
   - 驗收：只採用能改善已量測bottleneck且不破壞golden的方案；每次cache/mailbox
     topology、bank、lane或parallelism變更重跑Gate A/B及相關regression。若要把
     LayerNorm round trip改回DDR/DMA，視為Gate 1 transport變更而非局部優化。
   - Block：不得在 correctness未成立時同時引入多種 cache/prefetch optimization。

10. **建立 Vivado Zynq/AXI block design（P2）**

    - 前置：parameter/mailbox topology已由Gate 8/9收斂；external final-result packet
      與DMA mode候選及payload shape已備妥，尚未投入不可逆block-design接線。
    - 產物：Zynq `S_AXI_HP*`到custom parameter read與external AXI DMA、PS
      `M_AXI_GP*`到AXI BRAM Controller/4 KiB mailbox及accelerator AXI4-Lite、必要的
      Interconnect/SmartConnect、完整address map、sidebands、clock/reset/CDC、IRQ/
      timeout，以及DMA `S_AXI_LITE`分工；同時凍結final-result format/length、external
      frame ordering與是否使用stream ID/sideband。
    - 驗收：AXI protocol、CDC/reset檢查通過；完整synthesis含AXI BRAM Controller、
      mailbox、DMA/interconnect/FIFO；custom master只搬parameter，mailbox只搬
      LayerNorm 64/782-byte round trip，DMA只搬external ingress/egress；完整committed
      mailbox input才產生atomic valid。
    - Block：只有RTL AXIS或array-mailbox TB不算AXI BRAM Controller/DMA/block-design
      integration。

11. **完成 PS driver 與 transfer microbenchmark（P2）**

    - 前置：block design/address map固定，可使用測試 bitstream。
    - 產物：v3載入/驗證、parameter/external-DMA flush/invalidate、stage command、
      device/uncached mailbox mapping、MMIO barrier、slot/frame ownership、IRQ/polling、
      timeout/error recovery，以及依所選simple/SG mode的external DMA管理與可重跑
      microbench。Performance path應使用compiled driver/kernel或等價bulk MMIO方法，
      不以逐word Python操作作為唯一結果。
    - 驗收：先實測DDR->parameter cache、64-byte PL->PS mailbox read、782-byte PS->PL
      mailbox write/commit、完整CPU preprocessing round trip，以及external MM2S/S2MM；
      記錄clock、alignment、bytes、GP transactions、bursts/packets、並行client與
      DDR/device-memory policy。
    - Block：payload/clock理論值不能代替 sustained board transfer measurement。

12. **完整 implementation 與 PYNQ-Z1 板測（P2）**

    - 前置：RTL、fullband memory regression、runtime packet/system regression、
      block design、driver與microbench全部通過。
    - 產物：post-route reports、bitstream/software版本、board regression、完整
      latency/RTF/功耗/音訊品質與 error/reset recovery結果。
    - 驗收：記錄LUT/FF/DSP/BRAM、WNS/TNS、congestion、custom/DMA bandwidth、
      mailbox MMIO與PS preprocessing latency、PL cycles、end-to-end RTF；只有此gate
      可宣稱板上結果與real-time。
    - Block：OOC timing、XSim cycle count或單次 demo不能取代可重跑完整板測。

## 10. 第一版明確排除與變更規則

第一版不包含：

- parameter BRAM -> DDR writeback；
- feature/result 經 `memory.v`；
- weights/parameters由external AXI DMA或LayerNorm mailbox載入cache；
- fullband projection與normalized subband vectors先寫DDR再由DMA往返；
- mailbox payload經accelerator AXI4-Lite registers搬移；
- PL 端 row-major transpose；
- 全模型常駐 parameter BRAM；
- 預設三套 subband engine/cache；
- 未經 profile就啟用 512 KiB、active-source fetch、tile ping-pong或 multi-bit/cycle
  spike encoder。

若未來更換parameter/mailbox transport、讓DMA與custom master/mailbox共享同一資料、
改mailbox layout、external packet grouping、cache topology、lane count或parallelism，
必須：

1. 新增/更新跨任務 decision；
2. 依影響version v3 image、mailbox ABI或external packet ABI；
3. 更新 ownership/error/CDC契約；
4. 從受影響的最早 gate重跑，不得只重跑末端 demo。

## 11. 完成定義

本文件完成及第一版 standalone RTL通過，只代表 architecture、ABI、local services與
代表性 OOC checkpoint成立，不代表 memory subsystem完成。第一版結果與限制見
[Memory v1 設計與 PYNQ-Z1 可行性](MEMORY_V1_FEASIBILITY.md)。
Production memory完成必須同時具備：

- versioned v3 image及逐值golden；
- parameter loader + cache + memory service RTL/TB；
- dual-slot LayerNorm mailbox、AXI BRAM Controller integration與PS MMIO driver；
- stage barrier、mailbox commit barrier與full-size connected regression；
- representative OOC與完整 implementation；
- external ingress/egress Xilinx AXI DMA/block design與PS driver；
- DDR cache coherency、mailbox ordering/ownership、錯誤恢復、bandwidth、latency、
  RTF與板測記錄。

相關依據：

- [Memory integration analysis](MEMORY_INTEGRATION_ANALYSIS.md)
- [Memory RTL guide](MEMORY_RTL_GUIDE.md)
- [PYNQ-Z1 feasibility checklist](../PYNQ_Z1_FEASIBILITY_CHECKLIST.md)
- [Global FSM and subband schedule](../GLOBAL_FSM_AND_SUBBAND_SCHEDULE.md)
- [Parameter/runtime transport decision](../../team_workspace/decisions/2026-09-01-parameter-and-runtime-data-transport-partition.md)
- [Source-major weight layout decision](../../team_workspace/decisions/2026-09-01-sparse-column-packed-weight-layout.md)
