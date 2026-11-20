# PYNQ-Z1 模塊資格稽核與真實權重 sparse-read 分析

- 稽核日期：2026-09-01
- 目標：PYNQ-Z1 / `xc7z020clg400-1`
- Checklist：`docs/PYNQ_Z1_FEASIBILITY_CHECKLIST.md`
- 真實 blob：`upstream/parameters/parameters.bin`
- 自動報告：`outputs/memory/2026-09-01/sparse_parameter_read_report.json`

## 先說結論

目前 23 個 synthesizable RTL module 中，只有 `pe_requant_lane` 在「單一 lane」
範圍具備 bit-exact XSim、latency/II、指定 part OOC utilization 與 synth timing，可視為
通過獨立 module checkpoint；它仍未代表預定 5-lane requant 配置或完整 PE array 通過。

其餘 module 都尚未完成新版 PYNQ-Z1 Gate A/B。`gsu_layer`、
`fullband_three_layer` 與預設 512 KiB 的 `memory` 更不只是缺報告，而是目前結構已有
明確 blocker。`axis_int8_loopback` 是接線 test harness，不是 production block。所有
module 都尚未通過 Gate C，因為 `top.v`、global `fsm.v`、完整 `pe_array.v`、memory
service、DMA/block design、full-system synthesis/implementation 與板測都不存在。

這裡的「不符合資格」主要是 qualification evidence 或 scale 不足，不等同於已通過
testbench 的 RTL 行為一定有 bug。既有 20/20 XSim 證明的是 reduced/standalone
behavior；不能代替 PYNQ-Z1 資源、timing、DDR、RTF 或 board evidence。

## 判定標準

| 判定 | 意義 |
| --- | --- |
| Isolated PASS | 在明列的單模塊範圍通過 Gate B 核心證據；仍需 intended-count 與 Gate C |
| UNKNOWN / incomplete | 有部分行為證據，但缺 Gate A scaled estimate、OOC、throughput 或整合證據 |
| BLOCKED | 現行預設規模/介面已有容量或結構衝突，不能直接進整合 |
| Harness | 只用於接線驗證，不應列為最終 accelerator instance |

舊硬體 task 都建立在 feasibility checklist 之前；唯一本次 audit task 有正式
`## PYNQ-Z1 feasibility` 區段。因此以下是 retroactive audit，不會把缺失資料假裝成
已量測結果。

## 全部 RTL module 稽核

| Module | 現有證據 | PYNQ-Z1 判定 | 未通過項目 / 主要風險 |
| --- | --- | --- | --- |
| `axi_lite_control` | 2018.3 XSim self-checking PASS | UNKNOWN | 無 Gate A、OOC/IP packaging、AXI VIP、CDC/reset 與 PS driver/block-design 驗證 |
| `axis_int8_ingress` | `tb_axis_int8_link` PASS，含 keep/last/backpressure | UNKNOWN | 64-bit beat 被序列化成 1 byte/cycle；無 frame throughput budget、OOC、DMA/CDC 實測 |
| `axis_int8_egress` | `tb_axis_int8_link` PASS | UNKNOWN | 單 output register 造成 full beat 間 bubble；無 scaled FIFO/packet/RTF 與 OOC 證據 |
| `axis_int8_loopback` | 端到端 link TB PASS | Harness | 只是 ingress/egress wiring proof，不是最終 neural datapath |
| `axis_weight_loader` | 64→128-bit、partial/last/error TB PASS | UNKNOWN | 未接 BRAM/memory service；無 OOC、buffer depth、packet schedule、DMA 或 CDC 證據 |
| `deepfilter_complex_mac` | 單 MAC orders 1/3/5 行為 TB PASS | UNKNOWN | 每 instance 有四個 8×8 乘法；完整 bins/orders 排程、instance count、cycles 與 OOC 未定 |
| `gsu_gate_postprocess` | 單 leaf arithmetic TB PASS | UNKNOWN / high risk | 每 instance 有兩個未 pipeline 32×32 RQ；現行 GSU 需要 32 copies，無 scaled synth/timing |
| `gsu_state_update` | 單 leaf arithmetic/clipping TB PASS | UNKNOWN / high risk | 每 instance 有三個 32×32 RQ 加兩個小乘法；現行 GSU 需要 16 copies，無 scaled synth |
| `hybrid_pe` | 四 modes 與 accumulator TB PASS | UNKNOWN | full GSU/linear 會複製多 lane；乘法映射、DSP count、Fmax 與 reuse schedule 無 OOC |
| `integer_requantizer` | 單 combinational reference TB PASS | UNKNOWN / high risk | 32×32 multiplier + 64-bit variable shift 無 pipeline；在 legacy hierarchy 被大量複製 |
| `linear_postprocess` | 單 leaf requant/bias/saturation TB PASS | UNKNOWN | 16-lane projection 需 16 個 32×32 RQ；無 intended-count OOC/timing |
| `output_serializer` | ready/valid/index TB PASS | UNKNOWN / low risk | 缺 Gate A scaled interface/packet latency與 OOC；尚未接 AXI egress |
| `ping_pong_weight_buffer` | swap/read/write TB PASS | UNKNOWN | default 兩個 16 KiB banks，結構估算約 8 BRAM36；未 synth，深度只適合作 tile cache |
| `saturate_int8` | 邊界/clip TB PASS | UNKNOWN / low risk | 純 leaf 風險低，但仍缺 intended instance total 與整合 timing evidence |
| `sigmoid_lut` | LUT address/config TB PASS | UNKNOWN | 每 GSU lane 各複製一份 255×8 LUT；多讀 port/複製方式與 intended-count RAM mapping 未 synth |
| `signed_round_shift` | 正負/tie/shift TB PASS | UNKNOWN / high fanout risk | 64-bit variable shifter在 legacy RQ hierarchy大量複製；無 scaled LUT/timing report |
| `spike_indexer` | zero/sparse/dense/backpressure TB PASS | UNKNOWN | 320-bit vector 逐 bit scan，固定至少約 320-cycle scan；32-bit/cycle encoder與 RTF 未完成 |
| `sparsity_aware_matvec` | 320×320、16-lane synthetic XSim；read count正確 | UNKNOWN | 無 OOC/BRAM banking/physical memory；real weight只在本次 host reference驗證，未進 RTL TB |
| `gsu_layer` | reduced-dimension multi-frame XSim PASS | **BLOCKED current structure** | default full size未模擬/合成；16 lanes同時形成112個32×32 RQ、5,792-bit param response，未接真實 memory |
| `linear_projection` | reduced-dimension XSim PASS | UNKNOWN / high risk | full 320→64未模擬/合成；16個32×32 RQ、1,120-bit param response與真實 memory未接 |
| `fullband_three_layer` | reduced GSU1→GSU2→projection XSim PASS | **BLOCKED current structure** | 同時 instantiate兩個 legacy GSU與projection，共240個32×32 RQ；無 stage-load barrier、真實權重或 full-size synth |
| `memory` | TB source存在；目前2018.3 regression未含它 | **BLOCKED at default** | 512 KiB/64-bit cache結構估算約128/140 BRAM36；v2 row-major無法直接回128-bit column tile；無current OOC/XSim |
| `pe_requant_lane` | 5,155-vector XSim；latency 9、II=1；475 LUT/431 FF/4 DSP；5 ns OOC WNS +0.263 ns | **Isolated PASS** | 5-lane scaled estimate為2,375 LUT/2,155 FF/20 DSP，但4-lane bank、共享lane與完整PE尚未 synth/route |

### 最嚴重的三個 blocker

1. **Legacy GSU 乘法器複製。** `gsu_layer` 每 lane有兩個 gate postprocess
   （共四個32×32 RQ）及一個 state update（三個32×32 RQ），16 lanes合計112個
   concurrent 32×32 requantizer。`fullband_three_layer` instantiate兩個GSU再加
   projection的16個，合計240個。單是 operator count已超過220個DSP的device總量；
   32×32乘法通常還需要多於一個DSP。把部分乘法塞進LUT也沒有 timing/resource證據。
   因此 legacy fullband不能直接上板，必須走既定的4-lane local RQ + 1-lane shared RQ
   time-multiplex PE架構。
2. **預設 memory cache過大且layout不相容。** `65536 × 64-bit` 以72-bit/512-depth
   BRAM36幾何做結構估算約需128個BRAM36，即91.4%。它還只輸出64 bits，而consumer
   要128-bit packed column word。最大v2 stage 260,120 bytes以同樣幾何約64個
   BRAM36；單bank可作初始baseline，雙bank約128個又回到91.4% high risk。
3. **尚無可整合的parameter/memory service。** GSU每tile的parameter response為
   5,792 bits，projection為1,120 bits；目前blob內multiplier/shift仍是INT64，v2 matrix
   又是row-major。缺少range-checked lowering、packed record、64→128 adapter、stage
   barrier、cache ownership及非法位址處理。

## `parameters.bin` 實際內容

本次逐一重算blob與每個tensor的SHA-256、dtype×shape byte數、offset區間。220個
區間連續、無gap、無overlap，全部hash吻合。

| 項目 | 實際結果 |
| --- | ---: |
| Blob size | 2,193,288 bytes |
| Blob SHA-256 | `572da396d01fbc20a9ed23f17fbbb0c29e3539fe9f7c3c9eb8c1c2c82f22f894` |
| Operators | 12 = 8 GSU + 4 Linear |
| Operator tensors | 212 |
| Unlowered LayerNorm tensors | 8 / 2,896 bytes |
| Total tensors | 220 |
| INT8 | 1,802,112 bytes |
| INT32 | 25,664 bytes |
| INT64 | 229,632 bytes |
| UINT8 sigmoid LUT | 2,040 bytes |
| FLOAT64 scales | 130,944 bytes |
| FLOAT32 LayerNorm affine | 2,896 bytes |

八個GSU的`weight_ih_q`與`weight_hh_q`都是`[2H, input]`，兩個gate half逐byte
相同。本次16個GSU matrix half全部驗證相同後，只取前H rows；加上4個linear
matrix後：

- source INT8 weights（含重複gate halves）：1,802,112 bytes；
- shared-gate去重後有效weights：956,096 bytes；
- 可省掉的重複INT8 weights：846,016 bytes；
- 有效weight中的零值：37,112 / 956,096 = 3.8816%。

3.8816%是全體weight zero比例，不能取代activation sparsity。部分subband
projection個別有較高zero比例，可另開weight-compression研究；目前RTL並沒有
zero-weight index/codebook，不能把它算進本次節省。

8個unlowered FLOAT32 tensors是fullband 64與subband 46/94/158的LayerNorm
weight/bias。它們合計只有2,896 bytes，但LayerNorm arithmetic仍未fixed-point
lowering；依已接受的partition，fullband LayerNorm在host，subband LayerNorm在PS，
不應為了這些tensor在PL新增LayerNorm datapath。

完整raw blob約為PYNQ-Z1全部BRAM理論bit容量645,120 bytes的3.40倍；v2 compact
image 1,313,104 bytes仍約2.04倍。因此PS DDR + stage/tile cache不是選項，而是必要
條件。

## 為什麼目前不能直接「讀特定行」

數學上`y = W x`，spike index `i`選的是`W[:, i]`，也就是原矩陣的**欄**。
`parameters.bin`是C-order row-major：

```text
raw_byte(row, source) = tensor_base + row * input_size + source
```

所以同一source的16個lane相隔`input_size` bytes。例如：

| Matrix | lane stride | 要收集16 bytes所跨的raw範圍 |
| --- | ---: | ---: |
| fullband GSU1 `weight_ih_q` effective `[320,64]` | 64 B | 961 B |
| fullband GSU2 `weight_ih_q` / `weight_hh_q` `[320,320]` | 320 B | 4,801 B |
| subband GSU1 `[224,46/94/158]` | 46/94/158 B | 691/1,411/2,371 B |

這不是兩次相鄰64-bit read能完成的128-bit response。若讓RTL做gather，一個logical
word會變成16個strided byte access，先前的「weight read次數減少」就不等於實體
memory transaction減少。

已接受的v3 contract把矩陣轉成：

```text
stored_weight[source_index][row_tile][lane]
word_index = source_index * ceil(output_rows/16) + row_tile
```

此時使用者說的「特定行」就是轉置後的stored source row；每個row tile正好是連續
16 bytes，64-bit cache讀相鄰兩word即可組成16-lane response。對fullband 320-output
matrix，一個active source是20個連續128-bit words / 320 bytes；subband 224-output
matrix則是14 words / 224 bytes。

## 真實權重 selected-index 測試

測試對全部20個有效matrix執行五種pattern：zero、首/中/末index、約6.25%隨機、
約25%隨機及dense。每個pattern做兩條完全獨立的走法：

1. 從raw row-major tensor計算dense binary reference；
2. 依`source_index -> row_tile -> lane`組128-bit words，只讀active source並累加。

共20×5 = 100組結果逐一INT32 bit-exact相等；source-major packed payload也逐word
驗證lane order與raw gather相同。16個runtime真正可使用spike sparsity的matrix為：

- 八個GSU recurrent `weight_hh_q`；
- 四個第二層GSU input `weight_ih_q`；
- 四個projection `weight_q`。

四個第一層GSU input `weight_ih_q`接收dense normalized INT8 feature，不能用binary
spike skip；但其recurrent path仍可用。

以下把16個eligible matrix各執行一次的logical 128-bit read加總。這不是一個真實
audio frame的完整schedule，因為subband operator的呼叫次數與runtime trace尚未帶入。

| Pattern | Selected words | Dense words | Logical reduction |
| --- | ---: | ---: | ---: |
| zero | 0 | 54,304 | 100% |
| 3 active indices/matrix | 645 | 54,304 | 98.8122% |
| 約6.25% active | 3,394 | 54,304 | 93.75% |
| 約25% active | 13,576 | 54,304 | 75% |
| dense | 54,304 | 54,304 | 0% |

約6.25%案例相當於54,304 bytes selected weight payload，dense是868,864 bytes，
理論少814,560 bytes。這個比例正是`1 - active_density`；真正的速度提升還受encoder、
request latency、burst、cache hit、parameter讀取與compute schedule限制。

## 何時能真的減少DDR權重傳輸

如果每次layer開始仍把完整stage從DDR載入BRAM，sparse execution只減少BRAM read與
MAC工作量，**不會減少DDR stage-load bytes**。要把優點擴大到DDR，後續memory
service至少要做一種：

1. 先編碼active indices，再以source-major address從DDR只burst active source rows；
2. 以較小source/tile ping-pong cache保留跨frame常用資料並按需補入；
3. PS先根據index組weight packet，再經AXI4-Stream送入PL。

方案1最直接，但current sparse controller是`row_tile outer -> active index inner`；要得到
整條source row的DDR burst效率，scheduler/prefetch adapter需改成active-source grouping，
或先把整條source column暫存後再餵現有PE。這是下一個memory-service task要比較的
cycle/BRAM/AXI tradeoff。

## 建議的資格修復順序

1. 先完成`pe_local_requant_bank_4lane`，用5個已測lane的intended-count OOC結果取代
   legacy GSU的數百個combinational RQ。
2. 讓v3 generator輸出source-major weight words及range-checked packed parameters，
   用本次real-blob test作golden。
3. 實作獨立memory-service TB：兩個64-bit read組128-bit、selected index address、
   response hold、非法index及stage barrier。
4. synthesize 256 KiB single-stage cache與較小ping-pong tile cache，實測BRAM/Fmax後
   選方案；不要採用預設512 KiB作為上板baseline。
5. 以full-size 64→320→320→64與真實weights/spike trace做XSim，再合併module
   resource、AXI/DMA/FSM/CDC margin進Gate C。
6. 最後做implementation與PYNQ-Z1 board measurement，才可報DDR bandwidth、RTF、
   power與end-to-end latency。

## 證據界線

- Repository fact：module hierarchy、port width、blob/manifest、stored XSim/OOC report。
- 本次 measured host test：blob/tensor SHA、shared halves、packed byte order、100組
  dense-vs-selected integer結果與logical read counts。
- Analytical estimate：BRAM geometry、scaled multiplier count、logical payload reduction。
- 尚無：新增RTL XSim、除`pe_requant_lane`外的OOC synthesis、full implementation、
  DDR throughput、PS preprocessing latency、RTF、power及board result。
