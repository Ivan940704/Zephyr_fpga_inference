# Memory RTL：可驗證的 AXI/BRAM 控制器

這份文件對應 `rtl/memory/memory.v` 與 `rtl/tb/tb_memory.v`。它先把
memory 模組的責任縮成可驗證的硬體 contract，再說明如何接上團隊的 FSM 與
PE。附件原始交接文件保存在 `docs/memory/source_bundle/`，其中的路徑與後續工作
順序只是來源背景，不是目前專案指令；實際整合判斷見
`docs/memory/MEMORY_INTEGRATION_ANALYSIS.md`，production transport與12個驗收gate見
`docs/memory/MEMORY_DESIGN_GUIDELINES.md`。

## 1. 範圍與既有專案依賴

這份文件只說明本次新增的 Memory controller、memory image flow 與驗證環境，不重述既有 repository 的模型架構。

Memory RTL 不解析模型 layer 或 tensor shape；它只接受來源 byte address、BRAM 目的 word address與 byte count，並透過 AXI 將資料搬入 BRAM cache。Stage ordering、tensor offset 與 dtype 由 memory image flow 提供。

Image generator 使用新專案已經存在的：

```text
upstream/parameters/manifest.json
upstream/parameters/parameters.bin
```

Shared-gate repacking後，最大stage transfer已由470,040 bytes降為260,120 bytes，
可放入256 KiB BRAM並剩餘2,024 bytes。`memory.v`原始參數預設仍是512 KiB；production
correctness baseline已改成provisional 256 KiB single-stage parameter cache。CPU
LayerNorm round trip不從這個cache切空間，而使用另一個4 KiB dual-port mailbox BRAM。

## 2. 為什麼不能直接把 parameters.bin 當 AXI image

原始 blob 是 CPU-friendly 的連續 tensor archive；各 stage 的開始位置不保證符合所選 AXI beat 或 stage-alignment 要求，payload 長度也不一定是完整 bus beat。若直接用原始 offset 發出 parameter-loader 命令，可能違反 `memory.v` 的 alignment contract。

`rtl/tools/generate_axi_memory_image.py` 會：

1. 依 generator 定義的 stage execution order 重排 manifest 中的資料。
2. 讓每個 stage 的 DRAM 起點對齊 64 bytes。
3. 將 transfer size 補成完整 AXI beat。
4. 對 shared-weight GSU，確認兩個 gate 的 input/recurrent weights 與 weight scales 前後兩半逐 byte相同，只存一份供兩個 gate 共用；bias 與 requantizer 等 gate-specific tensor 不去重。
5. 產生 binary image、JSON map 與 Verilog 巨集。

執行方式：

```powershell
python3 rtl/tools/generate_axi_memory_image.py
```

預設輸出：

```text
outputs/memory/generated/parameters_axi.bin
outputs/memory/generated/memory_layout.json
rtl/memory/model_memory_map.vh
```

`outputs/memory/generated/` 是可重建衍生檔；已匯入且核對過的附件快照保存在
`outputs/memory/2026-09-01/`。`model_memory_map.vh` 可由 FSM include，並應與
manifest、binary image 和 JSON map 一起重新產生。

目前 layout format version 為 2：

| 項目 | 舊版 | Shared-gate packed v2 |
| --- | ---: | ---: |
| AXI image | 2,190,864 bytes | 1,313,104 bytes |
| 最大 stage transfer | 470,040 bytes | 260,120 bytes |
| 最大 BRAM words（64-bit） | 58,755 | 32,515 |

總共省下 877,760 payload bytes。JSON 會為共用 tensor 記錄 `gate_shared`、`gate_count=2`、source／packed shape 與 byte 數；Verilog header 會輸出對應的 `*_GATE_SHARED`、`*_GATE_COUNT` 與 `*_SOURCE_NBYTES`。

## 3. memory.v 的三個介面

### 3.1 FSM command

FSM 在 `cmd_valid && cmd_ready` 的 clock edge 送入一筆命令：

| Signal | 單位 | 意義 |
| --- | --- | --- |
| `cmd_src_addr` | byte | DRAM 中的 AXI byte address |
| `cmd_dst_word_addr` | BRAM word | BRAM 寫入起點；64-bit 設定下 1 word = 8 bytes |
| `cmd_byte_count` | byte | 要搬移的 byte 數 |
| `load_done` | pulse | 此命令結束 |
| `load_error` | status | 與 `load_done` 同 cycle 有效 |

來源位址與 byte 數都必須對齊 `AXI_DATA_WIDTH/8`。命令無效、超過 BRAM，或 AXI 回覆不是 `OKAY` 時，`load_error` 會拉高。

### 3.2 AXI DRAM read

控制器只實作 AXI read address (`AR`) 與 read data (`R`) channel，因此資料路徑只有 DRAM→BRAM。它沒有 AXI `AW/W/B` channels，也沒有 BRAM→DRAM store command／done／error 介面。PE 的 byte write strobe 只修改本地 BRAM，不能將資料寫回 DRAM。

Parameter loader 一次只發一個 outstanding burst，較容易第一次整合與除錯。每個 burst：

- 最多 `MAX_BURST_BEATS`，預設 16 beats。
- 使用 `INCR` burst。
- 不跨越 AXI 規定的 4 KiB boundary。
- 檢查 `RRESP` 與 `RLAST`。

若板卡提供 Xilinx MIG、Zynq HP/HPC 或其他 AXI interconnect，將這些 signal 接到 read master port。AXI ID、cache、prot、qos 等固定 sideband signal 可在 top-level wrapper 補上。

### 3.3 PE BRAM port

PE port 是同步讀取，latency 固定一個 clock：

```text
cycle N:     pe_rd_en=1, pe_addr=A
cycle N+1:   pe_rvalid=1, pe_rdata=BRAM[A]
```

`pe_wstrb` 每一 bit 控制一個 byte lane，因此 PE 可以更新本地 BRAM，而不必覆寫整個 64-bit word；這不構成 DRAM writeback。Loader port 與 PE port 可以同時工作，但不可在同一 cycle 存取相同 BRAM word；這種 collision 的結果依 FPGA BRAM primitive 而異。

## 4. 控制器內部狀態

```text
IDLE --合法 command--> AR --address handshake--> R
 ^                                               |
 |                     最後一個 beat             |
 +---------------- DONE <------------------------+
```

- `IDLE`：`cmd_ready=1`。
- `AR`：計算 burst 長度並保持 `ARVALID`，直到 `ARREADY`。
- `R`：每次 `RVALID && RREADY` 將一個完整 bus word 寫入 BRAM。
- `DONE`：將 `load_done` pulse 一個 cycle，下一拍回 `IDLE`。

這裡最重要的 RTL 觀念是 valid/ready handshake：只有兩者同時為 1 的 clock edge 才代表交易真的發生。valid 不能只 pulse 一拍後自行撤回。

## 5. FSM 如何載入一個模型 stage

假設 top-level 已知參數 image 的 DRAM base address `PARAM_BASE`，載入某一 stage 到 BRAM word 0：

```verilog
`include "memory/model_memory_map.vh"

cmd_src_addr      <= PARAM_BASE + `MODEL_FB_MODEL_SEQUENCE_MODEL_LAYERS_0_CELL_DRAM_OFFSET;
cmd_dst_word_addr <= 0;
cmd_byte_count    <= `MODEL_FB_MODEL_SEQUENCE_MODEL_LAYERS_0_CELL_TRANSFER_BYTES;
cmd_valid         <= 1'b1;
```

握手後 FSM 撤下 `cmd_valid`，等待 `load_done`；若 `load_error=1`，不可啟動 PE。

每個 tensor 在 stage 內的位置也會輸出成 `*_LOCAL_BYTE_OFFSET`。PE 要讀某個 INT8 值時：

```text
word address = local_byte_offset / 8
byte lane    = local_byte_offset % 8
```

INT32 與 INT64 資料使用 little-endian，必須從連續 byte lane 組合。矩陣 shape
與 flatten 順序應以 `outputs/memory/generated/memory_layout.json` 和原始
manifest 為準。這個 v2 image 仍維持原始 row-major tensor 順序，尚未變成現有
GSU/sparse engine 要求的 `{source_index, row_tile, 16 lanes}` physical layout。

Shared-gate tensor 的使用方式：

- Header 中 `*_GATE_SHARED=1` 表示 packed image 只有一份資料，forget gate 與 cell gate 都使用相同的 local byte offset。
- `*_NBYTES` 是 packed 後單份資料大小；`*_SOURCE_NBYTES` 是原始 archive 中兩份相同資料的總大小。
- Weight scale 也只存一份；但 bias、gate scale、input/recurrent requantizer multiplier／right shift 仍包含兩個 gate 各自的值，不能用相同位址取代。

## 6. testbench 驗證了什麼

`rtl/tb/tb_memory.v` 使用一個最小 AXI DRAM model，檢查：

1. 大於最大 burst 的搬移會正確拆成多個 burst。
2. 4 KiB boundary 前會先截短 burst。
3. Parameter loader 搬入 BRAM 的每個 64-bit word 都正確。
4. PE 同步讀取與 byte write strobe 正確。
5. 未對齊、零長度與 BRAM overflow 命令不會發出 AXI traffic。
6. AXI `SLVERR` 會傳到 `load_error`。

`rtl/tests/test_axi_memory_image.py` 另外驗證所有 shared-gate weight／scale halves
逐 byte 相同、packed image 只保留第一份、非共用 tensor 完整保留、最大 stage
不超過 256 KiB，以及目前 manifest 可重建已匯入的 binary/JSON 快照。

附件來源曾以 Vivado 2024.1 通過此 testbench；目前 outer repository 的主 regression
使用 Vivado 2018.3。匯入後尚未在這個工作環境重跑任何 Vivado 版本：

```powershell
powershell -ExecutionPolicy Bypass -File rtl/scripts/run_memory_xsim.ps1
```

也可分三步手動執行：

```powershell
C:\Xilinx\Vivado\2018.3\bin\xvlog.bat --sv rtl/memory/memory.v rtl/tb/tb_memory.v
C:\Xilinx\Vivado\2018.3\bin\xelab.bat tb_memory -s tb_memory_sim --debug typical
C:\Xilinx\Vivado\2018.3\bin\xsim.bat tb_memory_sim -runall
```

若使用 Icarus Verilog：

```powershell
iverilog -g2012 -s tb_memory -o rtl/build/tb_memory rtl/memory/memory.v rtl/tb/tb_memory.v
vvp rtl/build/tb_memory
```

成功時最後一行應為：

```text
PASS tb_memory
```

## 7. 與完整系統整合前的未完成項目與待定規格

目前 repository 已固定目標板為 PYNQ-Z1/XC7Z020，但以下整合規格仍未完成，不能
由這個 controller 單方面猜定：

1. 目前 v2 image 是 row-major tensor archive；需要 hardware-ready v3 packer，
   或一個會做 stride/gather 的 address adapter，才能回應現有 128-bit、16-lane
   weight request。
2. 參數 request 一次要求同一 tile 的多組 gate/state fields；仍需定義 BRAM layout、
   INT64 multiplier 到 32-bit port 的已驗證 lowering，以及 response buffering。
3. DRAM controller 的實際 HP port、AXI sideband、clock/CDC、base address，以及
   ownership/error規範對應的signal/register實作尚未建立。
4. Transport ownership已定案：本模組的custom AR/R只負責PL靜態parameter
   stage/tile cache；64-byte fullband projection與782-byte normalized subband input
   由獨立4 KiB mailbox、AXI BRAM Controller與PS `M_AXI_GP`搬移，不經DDR；Xilinx
   AXI DMA/AXI4-Stream只搬external fullband ingress/final egress。實際GP/HP ports、
   sidebands、DDR arbitration與block design仍未完成。
5. 預設 512 KiB cache 尚未 synthesis。以 XC7Z020 BRAM36 的 64-bit 組態做分析，
   它可能需要約 128/140 個 BRAM36；256 KiB 版本約 64 個。這只是結構估算，
   不是 Vivado utilization。
6. Parameter loader 與 PE 的同址 collision、stage ownership、reset/abort，以及是否
   加入 tile-level ping-pong/prefetch，仍需 RTL handshake 與 assertion。
7. AXI writeback尚未實作，且目前已接受的系統邊界不需要它：PL/PS LayerNorm
   intermediate經獨立mailbox BRAM直接共享，使用slot ownership與atomic commit；
   不得把mailbox誤接成此parameter cache的local writeback port。

因此目前 controller 是可驗證的「單 bank、DRAM→BRAM read-only raw stage cache」
基線，不是可直接接上 fullband 的完整 memory service。下一步應先固定 hardware-ready
tile/parameter layout 與 64→128-bit response adapter，再以 synthesis 結果決定 cache
深度、banking與prefetch；完整順序以
`docs/memory/MEMORY_DESIGN_GUIDELINES.md`為準。第一版不需要parameter writeback。
