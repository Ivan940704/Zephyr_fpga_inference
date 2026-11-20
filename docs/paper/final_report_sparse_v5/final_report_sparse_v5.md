# final_report_sparse_v5

日期：2026-09-14（Asia/Taipei）

用途：Zephyr 論文硬體實作與實驗結果補充；所有數值均對應 image
`0x00050002` 的保存證據。

## 1. 最終結論

Zephyr sparse-v5 在 PYNQ-Z1（XC7Z020-1）上以 32 個 PE、100 MHz、64-bit
AXI HP 邊界及 256-bit PL 內部 feed 完成實作。正式 100 檔測試使用單一
persistent runtime，關閉 software/hardware profiling 與逐幀 counter
snapshot，共完成 426,196 frames、3,408.768 秒評估音訊，100/100 PASS。

相對於原 image-v5，sparse-v5 將平均 START-to-output latency 由 6.6671 ms
降低至 **5.3943 ms（-19.09%）**，完整 frame iteration 由 7.0766 ms
降低至 **5.8076 ms（-17.93%）**，sustained board-loop RTF 由 0.886679
降低至 **0.728054（-17.89%）**。所有 100 個 enhanced WAV 的 SHA-256
均與原 image-v5 相同，因此本測試集上沒有量測到輸出或 SI-SDR 精度損失。

## 2. 論文結果總表

| 類別 | 指標 | Sparse-v5 結果 | 證據類型與範圍 |
|---|---|---:|---|
| 平台 | FPGA / device | PYNQ-Z1 / XC7Z020-1 | 實作目標 |
| 架構 | PE / clock | 32 / 100 MHz | routed full system |
| 介面 | AXI HP / internal feed | 64 / 256 bit | full-system design |
| 正規化 | LayerNorm | PL dynamic normalization + gamma/beta | image `0x00050002` |
| LUT | Slice LUTs | **42,773 / 53,200（80.40%）** | post-route |
| FF | Slice registers | **45,344 / 106,400（42.62%）** | post-route |
| BRAM | BRAM36 / BRAM18 | **76 / 7** | post-route |
| BRAM | BRAM36 equivalent | **79.5 / 140（56.79%）** | post-route |
| DSP | DSP48E1 | **68 / 220（30.91%）** | post-route |
| Slice | Occupied slices | **13,013 / 13,300（97.84%）** | post-route |
| Timing | WNS | **+0.251 ns** | 100 MHz full-system post-route |
| Timing | Guardbanded WNS / WHS | **+0.001 / +0.002 ns** | 0.25 ns setup、0.05 ns hold guardband |
| Timing | Raw hold margin | **+0.052 ns** | post-route |
| Latency | Mean START-to-output | **5.3943 ms/frame** | 100 檔實板、profiling off |
| Latency | Mean complete iteration | **5.8076 ms/frame** | 100 檔實板、profiling off |
| Latency | Frame p50 / p95 / p99 | **5.3616 / 6.0678 / 6.2897 ms** | 426,196 frames |
| Latency | Iteration p50 / p95 / p99 | **5.7752 / 6.4863 / 6.7180 ms** | 426,196 frames |
| Latency | Frame / iteration max | **12.8465 / 13.4523 ms** | Linux/Python outliers included |
| Throughput | Sustained board-loop RTF | **0.728054** | 100 檔實板 |
| Throughput | Setup-amortized board RTF | **0.732000** | 加入一次 runtime/parameter setup |
| Throughput | Full serialized PYNQ script RTF | **0.927193** | 含板上檔案處理；不含 PC 前處理 |
| Quality | Enhanced SI-SDR | **14.5120 dB** | 100 檔 clip arithmetic mean |
| Quality | SI-SDR improvement | **+7.4313 dB** | 相對 noisy input |
| Quality | Enhanced SNR | **14.7579 dB** | 100 檔 clip arithmetic mean |
| Correctness | Output match | **100/100 bit-exact** | 相對 frozen image-v5 enhanced WAV |
| Sparse memory | Parameter bytes saved | **54.47%** | 五檔、1,453 個 sampled frames |
| Sparse memory | Sparse load latency | **1.7835 ms/sample frame** | hardware counters at 100 MHz |
| Sparse execution | Request sparsity / MAC skip | **88.22% / 88.22%** | 五檔 sampled hardware profile |
| Power | Total on-chip power | **1.609 W** | Vivado vectorless post-route estimate |
| Power | Dynamic / static power | **1.462 / 0.147 W** | vectorless、Medium confidence |
| Energy | START-to-output energy | **8.679 mJ/frame** | estimated power × measured 5.3943 ms |
| Energy | Complete-iteration energy | **9.344 mJ/frame** | estimated power × measured 5.8076 ms |

論文若只保留一個 `energy/frame` 數字，建議採用 **9.344 mJ/frame**，因為它
對應完整 persistent frame iteration；表題或註腳必須註明這是 Vivado
vectorless PS+PL on-chip estimate，不是實體板卡電源軌量測，而且不包含外部
DDR、周邊及穩壓損耗。

## 3. 實作內容與論文敘述

Sparse-v5 保留 image-v5 的 32-PE datapath、PL LayerNorm、100 MHz 時脈及
host-precomputed STFT/magnitude 系統邊界。新增的 memory path 根據每一 stage
的 active lists 建立 matrix-wise union bitmap，只從 DDR 載入後續運算需要的
source rows，並在 cache 中維護 residency。若 stage 不符合 sparse 條件，則
回退至完整載入，確保 dense/sparse 數值契約一致。

LayerNorm 仍是每幀計算 mean、population variance 與 inverse standard
deviation，接著套用逐元素 gamma/beta affine；它不是以固定 affine layer
取代 normalization。STFT/magnitude 在電腦端預先計算，feature bundles 存入
板端記憶體後由 DMA 傳入 PL。輸出反量化、ISTFT 與 WAV 寫入不屬於 headline
board-loop latency。

## 4. 正式 100 檔實驗方法

- 測試檔：file ID 000–099，共 100 檔。
- 評估量：426,196 frames，3,408.768 秒有效音訊。
- Runtime：單一 persistent PYNQ runtime、參數載入一次。
- DMA：Python control、prepacked feature input、下一幀 host preparation 與當前
  frame execution 重疊。
- Profiling：software profiling off、hardware profiling off、counter snapshot 0。
- Safety：每檔結束及 session 結束進行 boundary diagnostic，共 101 次；不在
  `frame_loop_s` 範圍內。
- 最終狀態：control error 0、first fault 0，三個 DMA 均 idle 且 error-free。

### 4.1 Latency 定義

1. **START-to-output latency**：硬體接受 START，至 output S2MM DMA 完成。
2. **Complete frame iteration**：包含 DMA submit/admission、START、硬體執行、
   output copy 與必要的 frame retirement；不包含離線 ISTFT/WAV。
3. **Sustained board-loop RTF**：所有 `frame_loop_s` 總和除以有效音訊長度。
4. **Full serialized PYNQ-script RTF**：包含板上 feature load/packing、dequant、
   ISTFT/WAV 與 setup；仍不包含在 PC 產生 STFT/magnitude bundle 的時間。

Sustained RTF 0.728054 代表 throughput 比 real-time 快約 27.19%，且所有單檔
RTF 均低於 1（0.667830–0.789542）。但 iteration max 為 13.4523 ms，因此只能
宣稱平均、p99 與 sustained throughput 達到 8 ms hop 的 real-time 條件，不能
宣稱每一幀都保證在 8 ms 內完成。

## 5. Latency 組成

正式 100 檔 headline latency 不啟用 instrumentation。為定位組成，另以
file ID 000/025/050/075/099 執行 software profiling，hardware counter 每
16 幀 snapshot 一次。共 23,137 frames，只讀取 1,453 次 counter，相對逐幀
snapshot 減少 93.72%。下表僅作診斷，不取代正式 latency。

| Profile interval | Mean latency |
|---|---:|
| Ownership precheck | 0.010904 ms |
| Frontend packet preparation | 0.009906 ms |
| Spectrum packing | 0.005457 ms |
| Buffer/cache preparation | 0.005158 ms |
| DMA descriptor submission | 0.206648 ms |
| DMA input admission | 0.048352 ms |
| START acceptance | 0.050773 ms |
| START accepted → frontend service begin | 4.686246 ms |
| Projection handoff | 0.009926 ms |
| Subband transform | 0.005446 ms |
| Frontend commit | 0.005028 ms |
| Commit → output S2MM complete | 0.555113 ms |
| Output invalidate/copy | 0.161133 ms |
| Frame retirement/fault check | 0.096261 ms |
| Output dequantization/statistics | 0.603711 ms |
| ISTFT contribution | 0.910515 ms |

Software timestamping、每 16 幀的 counter snapshot、逐檔 runtime setup 使此
診斷 run 的 mean frame/iteration 為 5.4818/7.5952 ms；這些數字不可替換
profiling-off 的 5.3943/5.8076 ms。

## 6. Sparse-memory profiling

| Sampled hardware metric | Result |
|---|---:|
| Samples | 1,453 frames |
| Dense-equivalent stage bytes | 1,053,656.0 B/frame |
| Actual sparse stage bytes | 479,740.6 B/frame |
| Saved stage bytes | 573,915.4 B/frame |
| Byte saving | 54.47% |
| Sparse stage AR bursts | 4,070.0/frame |
| Sparse stage load cycles | 178,350.6 cycles/frame |
| Sparse stage load latency | 1.7835 ms/frame |
| AXI R wait latency | 0.8428 ms/frame |
| Profiled PL latency mean/min/max | 5.1907 / 4.4427 / 6.0967 ms |

以上為五檔 input-dependent hardware profile，不應寫成 100 檔 firing rate。
RTL two-frame traffic simulation另得到 2,107,312 dense bytes、865,808 actual
bytes、1,241,504 saved bytes（58.91%）；simulation 和 physical-board sampled
profile 必須分開標示。

## 7. Quality

正式 100 檔的 clip arithmetic mean：

| Metric | Noisy input | Sparse-v5 enhanced | Improvement |
|---|---:|---:|---:|
| SI-SDR | 7.0806 dB | **14.5120 dB** | **+7.4313 dB** |
| SNR | 7.0922 dB | **14.7579 dB** | **+7.6657 dB** |

Audio-duration-weighted enhanced SI-SDR/SNR 為 14.5045/14.7515 dB。論文與
表格若寫 `SI-SNR`，不可直接以此處的 SI-SDR 代入；PESQ、STOI、DNSMOS 亦
沒有在本次 sparse-v5 100 檔測試中重新量測。

五檔 gate 的 enhanced SI-SDR 分別為：

| File ID | SI-SDR | Mean frame | p99 frame | Mean iteration | p99 iteration |
|---:|---:|---:|---:|---:|---:|
| 000 | 14.8432 dB | 5.5058 ms | 6.2065 ms | 5.9113 ms | 6.6264 ms |
| 025 | 11.9486 dB | 5.3073 ms | 5.9392 ms | 5.7181 ms | 6.3833 ms |
| 050 | 2.1876 dB | 5.4314 ms | 6.1744 ms | 5.8275 ms | 6.5839 ms |
| 075 | 15.5373 dB | 5.4815 ms | 6.1691 ms | 5.8734 ms | 6.5893 ms |
| 099 | 17.3096 dB | 5.2131 ms | 5.9868 ms | 5.6112 ms | 6.3869 ms |

## 8. Image-v5 與 sparse-v5 差異

| Metric | Image-v5 | Sparse-v5 | Change |
|---|---:|---:|---:|
| Image ABI | `0x00050001` | `0x00050002` | sparse loader ABI |
| Mean START-to-output | 6.6671 ms | **5.3943 ms** | **-19.09%** |
| Mean iteration | 7.0766 ms | **5.8076 ms** | **-17.93%** |
| Frame p99 | 7.1957 ms | **6.2897 ms** | **-12.59%** |
| Iteration p99 | 7.6315 ms | **6.7180 ms** | **-11.97%** |
| Sustained board-loop RTF | 0.886679 | **0.728054** | **-17.89%** |
| LUT | 45,188 | **42,773** | **-5.34%** |
| FF | 42,151 | 45,344 | +7.58% |
| DSP48 | 65 | 68 | +4.62% |
| BRAM36 equivalent | 79.5 | 79.5 | unchanged |
| Slices | 13,159 | **13,013** | **-1.11%** |
| WNS | +0.250 ns | +0.251 ns | +0.001 ns |
| Guardbanded WHS | +0.016 ns | +0.002 ns | lower, still passing |
| Vectorless on-chip power | 1.642 W | **1.609 W** | -2.01% estimated |
| Complete-loop energy | 11.645 mJ/frame | **9.344 mJ/frame** | **-19.75% estimated** |
| Enhanced SI-SDR | 14.5120 dB | **14.5120 dB** | unchanged |
| Bit-exact output | baseline | 100/100 | preserved |

整體 latency 改善不能只歸因於單一 sparse row skip。Sparse-v5 同時改寫
stage loader/union planning、cache residency 與相關時序 pipeline；表格應稱為
完整版本 A/B，而 memory traffic saving 則由獨立五檔 hardware counters 支持。

## 9. Timing 與 clock 宣稱

100 MHz full-system route 的 WNS 為 +0.251 ns。若只以目前 critical path
算術換算，零 slack 約為 102.57 MHz；但加入 0.25 ns setup engineering
guardband 後只剩 +0.001 ns，因此 release clock 必須維持 **100 MHz**。
本結果不能用來宣稱 102 MHz timing closure。

## 10. Energy 證據邊界

Vivado 2018.3 vectorless post-route estimate：total on-chip 1.609 W、dynamic
1.462 W、device static 0.147 W、junction temperature 43.6 C，confidence
Medium。此估計涵蓋 Zynq PS+PL on-chip power；不包含外部 DDR、周邊、板上
regulator loss，也不是電源軌量測。

`E = P × t`：

- START-to-output：1.609 W × 5.394255 ms = **8.679 mJ/frame**。
- Complete iteration：1.609 W × 5.807605 ms = **9.344 mJ/frame**。

先前 source-method 的 nJ 級算術 proxy 與本處 mJ 級 SoC on-chip estimate
口徑不同，不可放在同一欄直接比較或用前者取代 FPGA energy/frame。

## 11. 論文中可安全使用的主張

- 32-PE、100 MHz sparse-v5 full-system route 在 XC7Z020-1 通過 setup/hold、
  routing 與 blocking DRC gate。
- 100 檔實板測試的 sustained board-loop RTF 為 0.728，平均與 p99 latency
  小於 8 ms hop。
- 相對 image-v5，平均 START-to-output latency 改善 19.09%，board-loop RTF
  改善 17.89%，100/100 outputs bit-exact。
- 五檔 sampled profile 顯示 parameter stage traffic 平均減少 54.47%。
- Post-route vectorless estimate 給出 1.609 W 與 9.344 mJ/complete frame
  iteration；必須使用 estimated/on-chip 等限定詞。

不可宣稱：每幀硬性 deadline、102 MHz closure、100 檔 firing rate、實體板卡
功耗、SI-SNR/PESQ/STOI/DNSMOS，或 sparse memory 單獨造成全部 19.09% latency
改善。

## 12. Evidence provenance

- Sparse result commit: `ca152b3`; report branch:
  `codex/sparse-v5-paper-report`.
- Sparse image: BIT SHA-256
  `2e3e893791a7744ef7d54849d1bce5fe5e9939b676ef0a386e63fe11c414e147`;
  HWH SHA-256
  `f51a32f4f3ec4903336a322521abccff5f5539f07efe76210124f2e6bcef6a4e`.
- Sparse summary SHA-256:
  `c3cd12954c10227da9d6503e6ffca042fda78ba4d6b7474a79cd634176c95ade`.
- Original image-v5 summary SHA-256:
  `79e79e7e577ae101d65f56e052b5cac431d4a2dd2ab12ce416c5984ed15b6065`.
- Formal regression: sparse branch 147 passed / 7 pre-existing evidence-test
  failures；原 image-v5 baseline 為 145 passed / 9 failures，兩個 current
  implementation-contract failures 已修正。

隨附 `tables_sparse_v5.tex` 可作為 LaTeX 表格起點。它是量測結果整理，不是
完整論文正文；作者仍應依投稿政策自行改寫敘述、核對引用並揭露工具使用範圍。
