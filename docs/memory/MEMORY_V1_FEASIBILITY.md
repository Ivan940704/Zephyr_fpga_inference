# Memory v1 設計與 PYNQ-Z1 可行性

- 日期：2026-09-02（Asia/Taipei）
- 目標：PYNQ-Z1 / `xc7z020clg400-1`
- RTL clock baseline：100 MHz、單一 clock domain
- 結論：第一版 correctness baseline 已完成；v3 artifact、單一共享 parameter
  cache/service、雙 slot LayerNorm mailbox、獨立 self-checking testbench 與兩個
  representative RTL OOC 均通過。尚未完成 global FSM/top、AXI BRAM Controller/
  interconnect、PS driver、external DMA、post-route implementation 與板測，因此不可
  宣稱完整 accelerator fit、RTF 或 board-ready。

本文件是 [Memory 設計準則](MEMORY_DESIGN_GUIDELINES.md) Gate 2 至 Gate 5 的第一版
實作證據。分析估算、RTL simulation、Vivado OOC 與尚未取得的整合／板級證據分開
記錄。

## 1. 第一版架構

```text
immutable parameters.bin
  -> host generate_memory_v3.py
  -> parameters_v3.bin in PS DDR
  -> memory.v read-only AXI4 AR/R loader
  -> one shared 256 KiB raw stage cache
  -> memory_service
       - 2 x 64-bit -> 128-bit source-major weight response
       - 5,792-bit GSU / 1,120-bit projection parameter response
       - 255-byte GSU sigmoid-LUT stream

PL fullband result (64 B)
  -> layernorm_mailbox FB slot 0/1
  -> PS M_AXI_GP + future AXI BRAM Controller
  -> PS normalized subbands (782 B + 2 zero pad B)
  -> layernorm_mailbox SB slot 0/1
  -> ordered PL byte stream
```

只有一個 parameter cache 與一個 native client service；各 stage 由 shared PE 依序
time-multiplex。第一版沒有 ping-pong parameter bank，也不支援三套 subband engine。
LayerNorm mailbox 是獨立的 4 KiB true-dual-port BRAM，不與 parameter cache、DDR
loader 或 external AXI DMA 混用。

## 2. v3 parameter image ABI

Canonical command：

```bash
python3 rtl/tools/generate_memory_v3.py \
  --manifest upstream/parameters/manifest.json
```

Generator 保留 `upstream/parameters/parameters.bin` 不變，輸出：

- `parameters_v3.bin`：1,053,056 bytes，SHA-256
  `2e1f102b9c83cddbbc135a8218938c666d526aaa0db66699f89a8c5a79054f69`；
- `memory_layout_v3.json`、`memory_golden_v3.json`、checksum manifest；
- `model_memory_v3_map.vh` 與 synthesizable 12-stage table；
- image magic `ZEPHYR3\0`、format version 3、64-byte header；
- weight physical order
  `{operator,matrix,source_index,row_tile,lane}`，每 word 16 個 INT8 lane；
- INT64 source multiplier 必須可無損 lowering 到 signed 32-bit；right shift 必須在
  unsigned 6-bit 範圍；任何越界都使生成失敗；
- GSU shared-gate 上下兩半逐 byte 相等才去重；
- GSU parameter record 為 5,792 payload bits / 728 transfer bytes；projection 為
  1,120 payload bits / 144 transfer bytes。lane 0 位於最低 bits，record 為 little
  endian，尾端 padding 必須為零；
- 每個 GSU stage 的 255-byte LUT 保持獨立 section，transfer padding 為零。

Python 測試逐一比對所有 source-major weight lanes、shared-gate duplicates、所有
parameter fields、padding 與 8 組 LUT，並以 temporary output 驗證全部 artifacts 可
byte-exact deterministic rebuild。

## 3. 真實 stage 容量與 DDR traffic

下表的 transfer bytes 是 loader 實際搬入 cache 的範圍；64-bit beats 固定為
`bytes / 8`。Burst 數假設 image base 4 KiB aligned、`MAX_BURST_BEATS=16`，並包含
不得跨 4 KiB 邊界造成的 split。

| ID | Operator | Bytes | 64-bit beats | AXI bursts | Cache margin |
| ---: | --- | ---: | ---: | ---: | ---: |
| 0 | FB GSU1 | 137,728 | 17,216 | 1,077 | 124,416 |
| 1 | FB GSU2 | 219,648 | 27,456 | 1,717 | 42,496 |
| 2 | FB projection | 21,056 | 2,632 | 165 | 241,088 |
| 3 | SB0 GSU1 | 70,976 | 8,872 | 555 | 191,168 |
| 4 | SB0 GSU2 | 110,848 | 13,856 | 867 | 151,296 |
| 5 | SB0 projection | 18,640 | 2,330 | 147 | 243,504 |
| 6 | SB1 GSU1 | 81,728 | 10,216 | 639 | 180,416 |
| 7 | SB1 GSU2 | 110,848 | 13,856 | 866 | 151,296 |
| 8 | SB1 projection | 44,736 | 5,592 | 350 | 217,408 |
| 9 | SB2 GSU1 | 96,064 | 12,008 | 751 | 166,080 |
| 10 | SB2 GSU2 | 110,848 | 13,856 | 866 | 151,296 |
| 11 | SB2 projection | 29,824 | 3,728 | 233 | 232,320 |

最大 stage 是 ID 1 的 219,648 bytes，低於 256 KiB cache，保留 42,496 bytes
（16.2%）margin；因此第一版不需要先切 tile 才能保證 correctness。

shared schedule 若每 frame 載入全部 12 stages，合計 1,052,944 bytes、131,618
beats。理想 zero-wait AXI model另需約 8,233 次 AR burst handshake；只計 beat 加 AR
為 139,851 cycles（100 MHz 下 1.399 ms），8 組 LUT 的 native configuration另約
2,552 cycles。這些是 controller lower bound，不包含 HP interconnect／DDR latency、
refresh、PS traffic、stage release、compute 或 backpressure。

若系統需求是 100 或 125 frames/s，完整 stage preload分別是 105.3 或 131.6 MB/s；
後者約占 64-bit、100 MHz port 之 800 MB/s raw bus width 的 16.5%，加入最少 AR
cycles後約占 17.5% clock cycles。這不是板上 throughput；若 contention 或 RTF 不過，
fallback 是 active-source/tile ping-pong cache、跨 frame reuse／batch schedule，或降低
同時 resident 的其他 BRAM，而不是複製三份 cache。

## 4. `memory_service` contract

- stage request只在 cache `INVALID` 時接受，image version、stage ID、64-byte base
  alignment、32-bit address overflow與 256 KiB capacity先檢查；
- loader完整結束且 GSU LUT 的 255 bytes 全被 consumer 接受後，才 pulse
  `stage_load_done` 並進入 `READY`；只有 `stage_ready_for_compute` 可解除 compute
  barrier；
- stage 必須以相同 ID 明確 release。錯誤 release 不會破壞 active cache；
- weight request使用 `{matrix,source,row_tile,tag}`，兩次同步 64-bit read組成 lane 0
  在低 bits 的 128-bit response；無 stall 時 request accept 到 response valid 為 5
  cycles；
- parameter request使用 `{row_tile,tag}`；GSU 讀 91 words（183-cycle
  accept-to-valid），projection 讀 18 words（37 cycles）。response、tag、kind、bit
  count與 error 在 backpressure 下保持不變；
- 第一版只允許一個 outstanding native request；weight 與 parameter 同時出現時
  weight 有 deterministic priority；
- AXI loader只使用 AR/R、一個 ID、一個 outstanding burst、INCR、最多16 beats，
  且切開 4 KiB boundary。它檢查 `RID/RRESP/RLAST`；abort／R-channel timeout停止
  cache writes，但會 drain 已接受的 burst；
- typed sticky error 需 `clear_error`，partial／aborted load永遠不能變成 READY。

## 5. LayerNorm mailbox ABI

| Region | Byte offset | Physical bytes | Ownership |
| --- | ---: | ---: | --- |
| FB slot 0 | `0x000` | 64 | PL fill -> PS read -> PS release |
| FB slot 1 | `0x040` | 64 | PL fill -> PS read -> PS release |
| SB slot 0 | `0x400` | 784 | PS claim/write/commit -> PL stream/release |
| SB slot 1 | `0x800` | 784 | PS claim/write/commit -> PL stream/release |

Port A 是 1,024 x 32-bit native BRAM interface，預留給 AXI BRAM Controller。PS
subband payload必須寫滿196個 full-word transactions；partial `WSTRB` 會 fail closed。
最後一個 word 的 bytes 782/783 必須為零，commit 才會把前782 bytes原子發布。
Port B 將64個 fullband bytes先以四個 byte pack成一個完整 word，並從 committed SB
slot依 index 0..781輸出。Vivado 2018.3 已確認 storage 為一顆 1K x32
true-dual-port RAMB36。

每 frame 的固定 payload MMIO 是16個32-bit FB reads與196個32-bit SB writes，共212
transactions／848 payload bytes；另有 FB release、SB claim、SB commit 三個 control
events，以及實際 driver選擇的 status/IRQ reads。125 frames/s 時 payload是26,500
transactions/s、106 kB/s；吞吐量很小，但 GP transaction latency、CPU LayerNorm與
poll/IRQ idle time仍須板測。

slot state、frame ID與完整 word bitmap決定 validity；reset/abort只清 ownership，
不把舊 BRAM bits當成新 frame。RTL對 early/late FB length、stale/duplicate claim、
write without owner、partial strobe、incomplete或bad-padding commit、wrong release、
port collision與inactivity timeout提供 sticky typed error。

## 6. Gate A intended-count 與 Vivado OOC

PYNQ-Z1 reference capacity為53,200 LUT、106,400 FF、220 DSP48E1、140 RAMB36。

| Block | Evidence | LUT | FF | DSP | RAMB36 | WNS @ 10 ns |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `memory_service` + one 256 KiB cache | Vivado 2018.3 post-synth OOC | 5,999 | 6,580 | 1 | 64 | +1.858 ns |
| `layernorm_mailbox` + 4 KiB storage | Vivado 2018.3 post-synth OOC | 1,120 | 801 | 0 | 1 | +1.647 ns |
| Simple sum（非 integrated synthesis） | analytical sum of the two OOCs | 7,119 | 7,381 | 1 | 65 | N/A |
| Simple sum占 XC7Z020 | analytical | 13.4% | 6.9% | 0.5% | 46.4% | N/A |

兩個 OOC 都是 `xc7z020clg400-1`、10.000 ns，0 failing setup endpoints；estimated
critical-delay Fmax分別為122.82與119.72 MHz。`check_timing` 顯示0 no-clock、0
multiple-clock、0 unconstrained internal max-delay pins；OOC top-level I/O沒有
input/output delay，且 `HD.CLK_SRC` 留待 top-level clock buffer，因此這些數字只支持
RTL內部 post-synthesis timing，不支持 integrated I/O、placement或routing。

沒有任何單項超過80%，但65 RAMB36已占46.4%，必須和 PE state/buffer、AXI DMA、
interconnect及其他 BRAM一起做 Gate B。5,792-bit parameter response造成寬 register/
fanout，是 integration congestion高風險；若 post-route失敗，優先改為窄化或分段
parameter stream並加入 BRAM output pipeline。

目前 OOC不含 Xilinx AXI BRAM Controller與PS/PL interconnect IP，因此 Gate 5 的
custom RTL／BRAM inference／100 MHz部分通過，但完整 Gate 5仍是 **PARTIAL**；必須
在 block design加入 IP cost與 clocks後才能 accepted。Gate A 對本文件指定的單
cache、單 mailbox、shared-PE topology判定為 **FEASIBLE WITH RISKS**；完整
accelerator fit仍是 **UNKNOWN**。

## 7. Verification 與後續 gate

已取得：

- Python：v3 source-to-image、determinism、range/error tests；
- Icarus與 Windows Vivado XSim：raw AXI loader、real-v3 memory service、mailbox
  self-checking TB；
- Vivado 2018.3：兩個 representative post-synthesis OOC、BRAM inference、utilization、
  timing summary與 `check_timing` reports。

尚未取得：

1. Gate 6：把 stage release/barrier與 mailbox publish/commit接入 global FSM；
2. Gate 7：`memory_service + mailbox + FSM + fullband` reduced integration；
3. Gate 8：full-size、multi-frame real-v3-image simulation；
4. Gate 9：PS driver、AXI BRAM Controller、external DMA與 cache/MMIO policy；
5. Gate 10/11：XC7Z020完整 implementation與 PYNQ-Z1 板測；
6. Gate 12：ABI／RTL／driver／bitstream release bundle。

完整機器產生的 OOC/XSim紀錄在
[`rtl/reports/memory_v1`](../../rtl/reports/memory_v1/)，摘要見
[`summary.md`](../../rtl/reports/memory_v1/summary.md)。
