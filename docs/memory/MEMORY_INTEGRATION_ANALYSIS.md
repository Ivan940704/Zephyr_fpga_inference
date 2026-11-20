# Memory RTL 與現有模塊整合分析

- 分析日期：2026-09-01（Asia/Taipei）
- 目標板：PYNQ-Z1 / XC7Z020
- 分析對象：上傳的 Memory-only bundle、目前 outer repository RTL，以及
  `upstream/parameters` 的實際 manifest/blob
- 後續定案：transport ownership 與完整 12-gate 實作順序以
  [Memory 設計準則](MEMORY_DESIGN_GUIDELINES.md) 為準。

## 結論先行

匯入的 `rtl/memory/memory.v` 可以保留為「PS DDR → PL BRAM 的 raw stage cache
loader」，但不能直接當成現有 fullband engine 的完整 `memory.v`。中間至少還缺一個
`memory_service` adapter，負責：

1. 將 logical `{layer, matrix, row_tile, source_index}` request 轉成已定案的
   source-major physical address。
2. 將兩筆 64-bit BRAM read 組成一筆 128-bit、16-lane INT8 weight response。
3. 將 manifest 內的 gate/state/projection tensors lower、依 tile 組裝成現有
   parameter response。
4. 在 layer 切換前完成 stage load，並阻止 compute 與 parameter loader/cache write
   port 對同址 BRAM 的碰撞。

更關鍵的是，現有 v2 image 只做 stage alignment 與 shared-gate 去重，矩陣仍是
row-major。這與 sparse/GSU engine 的 column/tile request contract 不同；若不先做
hardware-ready 重排，每一筆 16-lane weight response 需要 16 次 stride/gather，而不是
兩次連續 64-bit read。建議將 generator 升級成 v3 tile image，而不是把 gather 成本
留在 RTL。

```text
PYNQ PS DDR: hardware-ready parameter image
                 │ AXI read through Zynq HP/interconnect
                 ▼
     imported raw stage cache (`memory.v`)
                 │ 64-bit synchronous BRAM port
                 ▼
       missing `memory_service` adapter
        ├─ 2 x 64-bit -> 16 x INT8 weight response
        ├─ tile parameter unpack/lowering
        └─ sigmoid LUT configuration
                 │ native ready/valid
                 ▼
 fullband GSU1 -> GSU2 -> projection

CPU LayerNorm round trip is a separate, DDR-bypassing path:
PL fullband result <-> dual-slot 4 KiB BRAM mailbox
                   <-> AXI BRAM Controller / PS M_AXI_GP <-> PS preprocessing

External ingress/final egress remains a third path:
PS DDR <-> Xilinx AXI DMA <-> 64-bit AXI4-Stream <-> PL
```

## 證據層級

- **Repository fact**：直接來自目前 RTL、manifest、generated layout 或已接受的
  decision。
- **分析結論**：由介面寬度、shape、address order 或 XC7Z020 primitive geometry
  推導；不是 synthesis/board measurement。
- **附件既有證據**：來源文件記載曾以 Vivado 2024.1 通過 memory TB；本次匯入
  不把這項紀錄改寫成目前 Vivado 2018.3 的新測量。
- **尚無證據**：Vivado synthesis/implementation、timing、parameter/mailbox BRAM
  inference、AXI BRAM Controller/GP MMIO latency、Zynq HP sustained bandwidth、
  bitstream 與 PYNQ-Z1 board latency。

## 已分類的附件

| 附件路徑 | 現在位置 | 類別 |
| --- | --- | --- |
| `rtl/memory.v` | `rtl/memory/memory.v` | synthesizable raw cache RTL |
| `rtl/model_memory_map.vh` | `rtl/memory/model_memory_map.vh` | generated RTL ABI |
| `sim/tb_memory.v` | `rtl/tb/tb_memory.v` | self-checking TB |
| `sim/run_memory_xsim.ps1` | `rtl/scripts/run_memory_xsim.ps1` | simulator runner |
| `tools/generate_axi_memory_image.py` | `rtl/tools/generate_axi_memory_image.py` | image generator |
| `tests/test_axi_memory_image.py` | `rtl/tests/test_axi_memory_image.py` | image integrity test |
| `build/parameters_axi.bin` | `outputs/memory/2026-09-01/parameters_axi.bin` | verified snapshot |
| `build/memory_layout.json` | `outputs/memory/2026-09-01/memory_layout.json` | verified snapshot map |
| `docs/MEMORY_RTL_GUIDE.md` | `docs/memory/MEMORY_RTL_GUIDE.md` | current-path guide |
| `DESIGN_PROGRESS.md` | `docs/memory/source_bundle/DESIGN_PROGRESS.md` | historical handoff data |
| bundle `README.md` | `docs/memory/source_bundle/README.md` | historical handoff data |
| `REMOTE_UPLOAD_CHECKLIST.md` | `docs/memory/source_bundle/REMOTE_UPLOAD_CHECKLIST.md` | historical checklist data |

沒有任何檔案寫入 dirty 的 `upstream/` nested repository；附件根層 README 也沒有
覆寫目前專案 README。

## 目前 Memory baseline 實際提供什麼

### Command 與 AXI read

`memory.v` 預設為 32-bit AXI address、64-bit AXI data、16-bit BRAM word address，
即 `65536 x 64-bit = 512 KiB`；command 是來源 byte address、目的 BRAM word
address 與 byte count（`rtl/memory/memory.v:15-34`）。它只提供 AXI AR/R channels
（`rtl/memory/memory.v:45-58`），一次一個 outstanding burst，會限制 burst 長度並
切開 4 KiB boundary（`rtl/memory/memory.v:110-132`）。

非法對齊、零長度或 BRAM overflow 會在發出 AXI traffic 前結束並回報 error；
`RRESP`、early/missing `RLAST` 也會累積成 `load_error`
（`rtl/memory/memory.v:178-247`）。

### Local BRAM port

Loader port 寫入完整 64-bit word；local port 是一拍 latency 的 64-bit synchronous read，
另有 byte write strobe（`rtl/memory/memory.v:138-164`）。RTL 註解明確禁止 loader 與
local port 在同 cycle 存取同一 word。模組沒有 AXI AW/W/B，因此 local write 不會
回寫 DDR。

### v2 parameter image

目前 snapshot 有 12 stages、1,313,104 bytes；最大 stage 是 fullband GSU layer 2，
260,120 bytes / 32,515 個 64-bit words
（`outputs/memory/2026-09-01/memory_layout.json:1-28`）。generator 固定 12 個
operator 的執行順序（`rtl/tools/generate_axi_memory_image.py:21-34`），並驗證/刪除
shared GSU weight/weight-scale 的重複 gate half
（`rtl/tools/generate_axi_memory_image.py:79-126`）。

fullband 三個 stage 的目前範圍為：

| Layer | DRAM offset | Transfer bytes | 64-bit words |
| --- | ---: | ---: | ---: |
| GSU1 | 0 | 178,200 | 22,275 |
| GSU2 | 178,240 | 260,120 | 32,515 |
| projection | 438,400 | 22,288 | 2,786 |

三者連同 alignment 的 span 是 460,688 bytes；容量上可放進 512 KiB，但資源代價
不代表適合 XC7Z020。

## 與現有模塊相容及不相容的地方

| 項目 | 已相容部分 | 仍缺部分 |
| --- | --- | --- |
| Layer tag | fullband 使用 layer 0/1/2，剛好對應 image 前三個 stages | cache 本身不理解 layer，需 FSM/adapter 選 base |
| Handshake | compute weight/param 都是 one-request/response ready/valid；cache command 也有 ready/status | raw BRAM port沒有 request backpressure或 response hold，需 adapter |
| Weight value | manifest 與 compute 都使用 signed INT8 | compute 要 128-bit/16 lanes；cache 只回 64-bit raw word |
| Shared gates | image 與 GSU 都只需一份 shared input/recurrent weights | gate-specific bias/requant fields仍要分開組裝 |
| Parameter values | manifest 已有 bias、multiplier、shift、LUT | manifest multiplier/shift 是 INT64；ports是 32/6 bits，且一個 GSU response 共 5,792 bits |
| Stage order | image order是 GSU1→GSU2→projection | current fullband controller在 layer 間沒有 `load_done` barrier |
| Reset | 都可由 top wrapper控制 | cache 是 active-low `rst_n`；compute 多為 active-high `rst`；CDC/reset release未定 |
| PS/PL data | 既有64-bit AXI4-Stream adapters可保留給external ingress/egress；LayerNorm mailbox layout/ownership已定 | cache使用獨立custom AXI AR/R；4 KiB mailbox、AXI BRAM Controller、GP/HP ports、sidebands與block design尚未完成 |

現有 fullband 對外的 weight request 是 `weight_layer/matrix/tile/index`，response 固定
`LANES*8 = 128 bits`（`rtl/fullband/fullband_three_layer.v:29-37`）。parameter request
只帶 `layer/tile`，但 GSU response 同時提供兩個 gate 的 input/recurrent multiplier、
shift、bias，以及 previous/cellgate/BN fields；以 16 lanes 計算共 5,792 bits
（`rtl/fullband/fullband_three_layer.v:39-65`）。projection response則需 1,120 bits。

fullband controller 已經 multiplex 三個 engine 的 request/response
（`rtl/fullband/fullband_three_layer.v:208-246`），因此 memory service 不必再仲裁三個
同時 requester；但它必須遵守 active layer，並在 response stall 時保持資料穩定。

## 最主要的 blocker：physical weight layout

既有 sparse 決策定義每筆 logical request 為 `{column_index, row_tile}`，回傳該 tile
16 個 output neurons 的 INT8 weights。GSU 對 input/recurrent matrix 使用同一種
`{matrix_kind, row_tile, source_index}` contract。

以 GSU1 `weight_ih_q` 為例，v2 JSON 記錄 packed shape `[320, 64]`，但 generator
只把原 tensor bytes 原樣 append；除了 shared-half 去重外沒有 transpose
（`rtl/tools/generate_axi_memory_image.py:79-108`，
`outputs/memory/2026-09-01/memory_layout.json:83-118`）。C-order row-major 下：

```text
byte(row, column) = base + row * INPUT_SIZE + column
```

同一 `column` 的 16 個 lanes 相隔 `INPUT_SIZE` bytes。GSU1 stride 是 64 bytes，
GSU2 recurrent stride 是 320 bytes；兩筆相鄰 64-bit reads不可能直接得到一個
16-lane column tile。若 RTL gather，每個 logical weight response至少要做 16 個
strided accesses，會破壞目前 sparse read-count所代表的 physical bandwidth假設。

後續 real-blob sparse-read audit已將v3 physical order定為source-major，讓一個
active source的所有row tiles可形成連續DDR burst；logical request欄位不變：

```text
weight_word[layer][matrix][source_index][row_tile][lane]
physical_128b_index =
    matrix_base + source_index * row_tile_count + row_tile
```

每個 128-bit word再拆成連續 lower/upper 64-bit words給目前 raw cache。generator 應
以 dense reference逐值驗證 transpose，並讓 JSON/header明確記錄 layout version、
lane order、matrix base、tile stride與source stride。current compute controller仍以
row tile為外迴圈；若要取得完整source-row DDR burst效益，memory service還需prefetch
整條source或調整schedule。完整stage preload不會因sparsity減少DDR bytes。

## Parameter lowering 與 LUT

v2 image仍包含 current compute ports不直接消費的 FLOAT64 scale metadata，也把
requantizer multiplier/right-shift保留為 INT64。對目前 fullband blob做唯讀檢查後：

- 所有 fullband requantizer multipliers 範圍為 536,900,783..1,073,674,818，能放入
  signed 32-bit。
- 所有 fullband right shifts 範圍為 20..33，能放入 6-bit unsigned field。

這是目前 blob 的分析結果，不是可對未來模型永久假設。v3 generator應在縮位前逐值
assert range，輸出實際 32-bit multiplier與6/8-bit shift；若任何值越界就停止生成，
不能在 RTL直接截掉高位。FLOAT64 calibration fields若沒有對應 runtime port，應留在
JSON provenance而不占用 PL stage cache。

建議每個 GSU param tile預先排成 adapter消費順序，adapter可用多 cycle讀完整 tile，
鎖存在 response register後才assert `param_rsp_valid`。兩個 fullband sigmoid LUT各有
255 bytes，應在 layer開始前透過既有 `sigmoid_cfg_*` port初始化，而不是混在每個
param response內。

## Cache 深度與 layer scheduling

以下是結構估算，不是 Vivado utilization：XC7Z020有140個BRAM36；若 inferred memory
以 64-bit word映射到 72-bit BRAM36配置，512 KiB (`65536 x 64`) 約需128個
BRAM36，單是cache就只剩12個。256 KiB (`32768 x 64`) 約需64個，且最大v2 stage
只剩2,024 bytes餘裕。

可選策略：

| 策略 | 優點 | 代價/風險 |
| --- | --- | --- |
| 512 KiB常駐fullband三stage | current controller不用layer load barrier | 分析估計約128/140 BRAM36，幾乎沒有compute/FIFO空間 |
| 256 KiB單stage cache | 三個stage都各自放得下，約64 BRAM36 | 每layer切換要reload；current controller無等待狀態 |
| 小型tile ping-pong cache | BRAM較合理，可prefetch | controller/generator/parameter-loader最複雜，需量測DDR持續bandwidth |

建議先用256 KiB單stage cache完成behavioral integration，再依synthesis與parameter-loader量測
收斂成tile-level ping-pong。為此 fullband controller需在 GSU1、GSU2、projection
開始前加入 `stage_req/stage_ready` barrier；目前它在 `STATE_START_L2` 與
`STATE_START_PROJ` 直接啟動下一engine（state definitions/starts 見
`rtl/fullband/fullband_three_layer.v:97-105,185-198`，實際 transition 見
`:408-445`），沒有足夠時間覆寫整個cache。

既有 `axis_weight_loader.v` 已能把兩個64-bit AXI4-Stream beats組成128-bit word
（`rtl/axi/axis_weight_loader.v:3-29`），`ping_pong_weight_buffer.v` 也有兩個128-bit
banks（`rtl/leaf/ping_pong_weight_buffer.v:3-44`），但目前只在獨立TB相接。它們是
歷史 prototype 證據，不再是 production parameter source-of-truth。

4 KiB LayerNorm mailbox是另一顆獨立dual-port BRAM，不從256 KiB parameter cache
切位址。以`1024 x 32-bit`結構估算約1個BRAM36，但asymmetric Port B、AXI BRAM
Controller/interconnect與timing必須用Vivado驗證；不能把這個估算當成utilization。

後續分工已定案為：`memory.v`透過HP/interconnect以custom AXI AR/R直接讀PS DDR的
PL靜態parameter image；PS LayerNorm的64-byte fullband output與782-byte normalized
subband input透過GP-mapped 4 KiB mailbox、不經DDR controller；Xilinx AXI DMA與
64-bit AXI4-Stream只搬external fullband ingress/final egress。64->128-bit組合移到
parameter cache與`memory_service`邊界。若未來改transport，必須另立versioned
ownership/cache contract，不能讓兩條路徑同時擁有同一bank或frame。

## CPU LayerNorm 與 writeback

附件來源文件把「BRAM→DRAM writeback後交給CPU LayerNorm」列為下一步，但目前已接受
的專案邊界不同：fullband LayerNorm在外部host；subband unfold/concat/LayerNorm/INT8
packing在PYNQ PS。PL先把完整64-byte fullband projection寫入mailbox output slot，
CPU透過`M_AXI_GP`/AXI BRAM Controller直接讀取；CPU完成782-byte subband payload後，
寫入另一個mailbox input slot並以frame ID atomic commit。這段不使用DDR或AXI DMA。

因此parameter cache繼續專注於read-only parameters，且不需要新增BRAM→DRAM
writeback。Mailbox使用獨立dual-port BRAM與slot ownership；payload映射為device/
uncached memory，commit/release前後使用MMIO ordering barrier，而非DDR cache
flush/invalidate。只有未來正式把activation/state放入parameter cache並要求PS共享時，
才需要重新定義AW/W/B與writeback。

## 建議的實作順序

本分析最初的六項建議已依 dependency、PYNQ-Z1 Gate A/B/C 與板測證據需求，展開為
12個不可跳關的實作與驗收 gate。正式順序、每關前置條件、必要產物、驗收與 blocker
統一見 [Memory 設計準則：十二個實作與驗收關卡](MEMORY_DESIGN_GUIDELINES.md#9-十二個實作與驗收關卡)。
