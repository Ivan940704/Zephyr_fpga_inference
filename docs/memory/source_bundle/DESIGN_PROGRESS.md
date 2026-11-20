# Memory RTL 設計進度交接

更新日期：2026-09-01（Asia/Taipei）  
來源分支：`fpga-inference`  
來源提交：`13ea1405c9a400aac647025a42b216975765a9bb`  
狀態說明：Memory RTL、image repacker、testbench 與本交接文件目前仍是工作目錄中的未提交變更。

## 1. 交接範圍

新的遠端專案已經匯入 `allen_Zephyr` repository 的原始內容。本交接只包含這次 Memory controller 討論後新增或衍生的項目：

- AXI4 read DMA＋BRAM cache RTL。
- 供後續 FSM／PE 使用的 memory-map header。
- 將既有 packed parameters 轉成 AXI-aligned stage image 的工具。
- memory layout／AXI image 衍生檔。
- Memory RTL testbench、模擬腳本與使用指南。

下列既有內容不會重複打包或重新說明：模型架構、model config、Python inference reference、原始 `parameters/manifest.json`、`parameters/parameters.bin`、checkpoint、一般架構文件與 repository LICENSE。

## 2. 已完成項目

### 2.1 Memory RTL baseline

已完成可綜合的 `rtl/memory.v`，內容為單一 AXI4 read DMA 加上 true-dual-port BRAM cache：

- FSM command 介面：`cmd_valid/cmd_ready`、來源 byte address、BRAM 目的 word address與 byte count。
- AXI4 read master 的 AR/R channels；一次一個 outstanding burst。
- 可參數化 AXI address width、data width、BRAM depth 與 maximum burst beats。
- 自動拆分長 transfer，且 AXI INCR burst 不跨越 4 KiB boundary。
- 檢查 `RRESP`、early/missing `RLAST`、未對齊命令、零長度與 BRAM overflow。
- PE 端為一拍 latency 的同步 BRAM read port，並提供 byte write strobe。
- 預設 64-bit AXI、`BRAM_ADDR_WIDTH=16`，等價於 512 KiB cache。

目前是「單 bank、完整 stage cache」基線。尚未加入 ping-pong、multi-bank、multiple outstanding bursts 或 clock-domain crossing。

### 2.2 Memory image repacking

已完成 `tools/generate_axi_memory_image.py`。工具讀取新專案既有的：

```text
parameters/manifest.json
parameters/parameters.bin
```

並產生：

```text
build/parameters_axi.bin
build/memory_layout.json
rtl/model_memory_map.vh
```

處理內容：

- 依 manifest 中目前部署 stage 的執行順序重排資料。
- 每個 stage 起點對齊 64 bytes。
- 每筆 DMA transfer 補齊為完整的 8-byte AXI beat。
- 對 shared-weight GSU，逐 byte 驗證兩個 gate 的 `weight_ih_q`、`weight_hh_q`、`weight_ih_scale` 與 `weight_hh_scale` 前後兩半相同，AXI image 只保留一份並由兩個 gate 共用。
- Gate-specific 的 bias、gate scale、input/recurrent requantizer multiplier／right shift 並不相同，仍各自完整保留。
- 輸出 stage DRAM offset、transfer size、BRAM words 與 tensor local byte offset。

目前衍生結果：

| 項目 | 原始 repack | Shared-gate repack | 減少量 |
| --- | ---: | ---: | ---: |
| AXI image | 2,190,864 bytes | 1,313,104 bytes | 877,760 bytes |
| 最大 stage transfer | 470,040 bytes | 260,120 bytes | 209,920 bytes（44.7%） |
| 最大 64-bit BRAM words | 58,755 | 32,515 | 26,240 |

新的最大 stage 可放入 256 KiB（32,768×64-bit）BRAM，剩餘 2,024 bytes；目前 `memory.v` 預設仍保留 512 KiB，待 activation、state 與 CPU round-trip buffer topology 確定後再決定是否縮小。

`memory_layout.json` 已升級為 format version 2，會標示 `gate_shared`、source／packed shape 與 bytes saved；`model_memory_map.vh` 也會輸出 `*_GATE_SHARED`、`*_GATE_COUNT` 與 `*_SOURCE_NBYTES`。這些都是生成檔；manifest、packing、bus width、stage ordering 或 alignment 改變時，必須和 binary image 一起重新產生。

### 2.3 驗證狀態

2026-08-31／2026-09-01 重新驗證結果：

- Vivado Simulator 2024.1 成功 compile、elaborate、run。
- Self-checking testbench 結果：`PASS: all memory controller tests passed`。
- 已覆蓋 maximum-burst split、4 KiB boundary、DMA data correctness、PE read、byte write strobe、非法命令與 AXI `SLVERR` propagation。
- Python image／manifest integrity tests 通過；所有 8 個 GSU stages 的 32 個 shared-gate weight／scale tensors 都驗證為前後兩半逐 byte 相同，其他 gate-specific tensors 不會被錯誤去重。
- 重新執行 image generator 後，AXI image、JSON map 與 Verilog header 和現有版本完全一致。

## 3. Memory RTL 介面摘要

### 3.1 Command interface

一筆命令在 `cmd_valid && cmd_ready` 的 clock edge 被接受：

| Signal | 單位 | 用途 |
| --- | --- | --- |
| `cmd_src_addr` | byte address | 外部 DRAM image 中的來源地址 |
| `cmd_dst_word_addr` | BRAM word address | BRAM cache 寫入起點 |
| `cmd_byte_count` | bytes | 搬移長度 |
| `load_busy` | status | controller 正在處理命令 |
| `load_done` | one-cycle pulse | 命令結束 |
| `load_error` | status with `load_done` | 命令或 AXI protocol 錯誤 |

來源位址與長度必須對齊 `AXI_DATA_WIDTH/8`。

### 3.2 AXI interface

目前只實作 AXI read-address／read-data（AR/R）channels，因此資料路徑只有 DRAM→BRAM。PE 端的 `pe_wstrb` 只會修改本地 BRAM，不能把內容寫回 DRAM；目前沒有 AXI AW/W/B channels，也沒有 BRAM→DRAM 的 store command／done／error 介面。Top-level wrapper 仍需依實際 AXI interconnect 補齊 ID、cache、prot、qos 等 sideband signals。

### 3.3 PE-side BRAM interface

- 同步 read，固定一拍 latency。
- 支援本地 BRAM byte write strobe；這不是 DRAM writeback 路徑。
- DMA 與 PE 不可在同一 cycle 存取同一個 BRAM word；collision 結果依實際 FPGA memory primitive 而異。

## 4. 尚未實作／尚待決定的 Memory 架構

1. FPGA／board 型號與可用 BRAM、URAM 容量。
2. DRAM controller 的 AXI address/data width、clock frequency、clock domain 與 image base address。
3. BRAM→DRAM writeback DMA 尚未實作。需定義 store command/status、AXI AW/W/B、burst 與 4 KiB boundary、alignment／write strobe、`BRESP` error propagation，以及與 DRAM→BRAM DMA／PE port 的 arbitration 與 buffer ownership。
4. CPU 執行 LayerNorm 的資料往返與控制路徑尚未實作。預期 shared-DRAM 流程為：FPGA 將 BRAM 中的 LayerNorm input 寫回 DRAM → 通知 CPU → CPU 讀取、計算並將 result 寫回 DRAM → 通知 FPGA → FPGA 以既有 read DMA 載回 BRAM並繼續。仍需決定 input/output buffer address 與 lifetime、通知方式（interrupt／MMIO doorbell／polling）、memory ordering／cache coherence、timeout／error recovery 及 FSM 暫停／恢復條件。
5. PE 每 cycle 所需的 memory bandwidth，及相應的 BRAM banking／port 數。
6. Parameter cache、activation buffer、recurrent-state buffer 與 CPU LayerNorm buffers 是否分離。
7. Shared-gate packing 後雖然單一最大 stage 已可放入 256 KiB，但加入 activation／state／CPU buffers 後是否仍採完整 stage cache；若不可行，需要由 FSM 與 PE 共同定義 tiling contract。
8. 是否需要 ping-pong buffers、prefetch 與 multiple outstanding AXI bursts。
9. Read DMA、writeback DMA 與 PE 同址 collision 的禁止條件、assertion 或 arbitration。
10. Reset、error recovery、command timeout 與 stream／utterance 切換時的 memory ownership。
11. Vendor memory primitive、read-during-write mode、synthesis constraints 與 CDC wrapper。

## 5. 建議後續順序

1. 將 shared-gate packing format v2、AXI image、JSON map 與 header 作為同一版本集合合併到新專案，並鎖定 generator regression test。
2. 固定 target board、AXI width／clock／clock domain、CPU 與 FPGA 的 shared-DRAM 可見性／coherency、image base address 與 PE bandwidth target。
3. 依新的 260,120-byte 最大 stage 與可用 BRAM／URAM，定義 parameter、activation、recurrent state、CPU LayerNorm input/output buffers 的地址、lifetime 與 ownership，再決定完整 stage 或 tiled cache。
4. 定義雙向 DMA contract：保留 DRAM→BRAM load，新增 BRAM→DRAM store command/status、AXI AW/W/B、read/write/PE arbitration 與 collision policy。
5. 實作並單獨驗證 BRAM→DRAM writeback，包括 burst split、4 KiB boundary、backpressure、data correctness、`BRESP`、非法命令與 BRAM range error。
6. 定義並驗證 CPU LayerNorm end-to-end handoff：store input、通知 CPU、CPU 完成通知、load result、FSM resume，同時處理 cache maintenance、ordering、timeout 與 error recovery。
7. 再依 PE bandwidth 與 CPU handoff latency 決定 banking、ping-pong、prefetch 與 multiple outstanding bursts。
8. 加入 ownership／collision assertions、command timeout，以及 reset／stream-switch recovery。
9. 執行 synthesis／timing／BRAM inference／CDC 檢查並調整 parameters 或導入 vendor primitives。
10. 建立板端 DRAM→BRAM、BRAM→DRAM 與 CPU LayerNorm round-trip 測試，並核對 image／map／header 同版。

## 6. Memory-only 交接包

`handoff/rtl_upload_bundle/` 已保留可直接合併到新 repository 根目錄的相對路徑；`handoff/rtl_upload_bundle.zip` 是相同內容的壓縮檔。

交接包只包含：

```text
rtl/memory.v
rtl/model_memory_map.vh
sim/tb_memory.v
sim/run_memory_xsim.ps1
tools/generate_axi_memory_image.py
tests/test_axi_memory_image.py
docs/MEMORY_RTL_GUIDE.md
build/parameters_axi.bin
build/memory_layout.json
DESIGN_PROGRESS.md
REMOTE_UPLOAD_CHECKLIST.md
README.md
```

新專案既有的 `parameters/manifest.json` 與 `parameters/parameters.bin` 是 generator 的輸入，但不會在本交接包中重複提供。

## 7. 重要整合注意事項

- `cmd_src_addr` 與 `cmd_byte_count` 必須對齊 `AXI_DATA_WIDTH/8`。
- `cmd_dst_word_addr` 是 BRAM word address，不是 byte address。
- `load_error` 只在 `load_done` pulse 的 cycle 有效。
- 現有 RTL 只有 DRAM→BRAM load；任何 BRAM→DRAM 或 CPU LayerNorm round-trip 都尚未實作。
- `parameters_axi.bin` 應由系統軟體載入到 `PARAM_BASE`；header 的 stage offset 是相對於此 base 的 byte offset。
- `memory_layout.json`、`parameters_axi.bin` 與 `model_memory_map.vh` 必須由同一次 generator 執行產生。
- `*_GATE_SHARED=1` 的 weight／scale tensor 在 image 只存一份；PE 必須讓 forget gate 與 cell gate 重用相同位址。Bias 與 requantizer metadata 仍是 gate-specific，不能共用。
- 目前 `memory.v` 使用 inferred BRAM array；導入指定 vendor primitive 前，需確認 synthesis report、read-during-write 與 true-dual-port inference 行為。
