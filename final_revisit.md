# Zephyr FPGA inference 最終回訪、最佳化與論文實驗計畫

- 文件日期：2026-09-07（Asia/Taipei）
- 目標平台：PYNQ-Z1 / `xc7z020clg400-1`
- 目前工作分支：`codex/overnight-board-bringup`
- 已驗證基線 commit：`354de28`（hardware baseline `1cb0724`）
- 本文件性質：未來執行計畫、實驗規格與完成定義；文件中的目標值不是已取得的結果

## 1. 最終目標

將目前已能在 PYNQ-Z1 上正確完成音訊 inference 的 Sequential-v4 accelerator，推進成可供
論文投稿的完整硬體／軟體共同設計證據。最終至少要同時回答以下問題：

1. FPGA 輸出是否與凍結的量化軟體參考一致？
2. 對完整 PTQ 評估集合的語音品質是否穩定改善？
3. 系統是否達到持續 real-time，而不只是單一 frame 或平均值看起來足夠快？
4. latency 分別花在 STFT、PS LayerNorm、mailbox、DMA、parameter loading、PE、
   DeepFilter 與 ISTFT 的哪一段？
5. sparse mode 實際少做多少 MAC、少讀多少 DDR bytes，又換來多少 latency／energy 改善？
6. 完整設計的 post-route timing、資源、實體板級功耗與每 frame 能量是多少？
7. 長時間執行、reset、DMA／mailbox錯誤恢復是否可靠？

論文預定主張可定位為：在資源受限的 XC7Z020 上，透過 INT8 量化、sparsity-aware
sequential PE、parameter streaming 與 PS–PL 協同設計，完成神經語音增強模型的實際
FPGA 部署，並量化品質、資源、延遲、稀疏度與能耗間的取捨。

## 2. 已取得且必須保留的基線

### 2.1 功能與品質

- Release BIT SHA-256：
  `2f6e7cc9d58a490a3aa44f092a9816c62eefd890edb2aa0a1824335af31899aa`。
- Sequential-v4 parameter image SHA-256：
  `e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34`。
- PYNQ 3.0.1 已連續完成 13,085 frames，frame ID 由 33 連續前進到 13,118。
- 三個 DMA 最終均為 Idle，control、mailbox 與 accelerator fault 均為 0。
- 先前 33-frame 測試的 16,896 個 complex accumulator components 與獨立 NumPy
  integer oracle 完全相等。
- 三筆代表性 PTQ 音訊的 SNR 改善為 `+18.769`、`+6.288`、`+0.548 dB`；串接後由
  `2.863 dB` 改善到 `16.881 dB`，改善 `+14.019 dB`。
- 目前三筆完整實板報告位於
  [rtl/reports/accelerator_full_board/ptq_three_case_20260907/summary.md](rtl/reports/accelerator_full_board/ptq_three_case_20260907/summary.md)。

### 2.2 延遲基線

音訊規格為 16 kHz、FFT size 512、hop size 128，因此每個新 frame 的 real-time 預算是
`128 / 16000 = 8 ms`，需求吞吐率是 125 frames/s。

| 實測區段 | 加權平均時間／frame | End-to-end 占比 | RTF 貢獻 | 證據邊界 |
| --- | ---: | ---: | ---: | --- |
| PS mailbox service | 16.742 ms | 42.38% | 2.093 | 直接量測 |
| START 期間其餘 PL／parameter／output DMA | 9.626 ms | 24.37% | 1.204 | START 總時間扣除 mailbox |
| Board loop 中 START 前後的量化、DMA/cache與統計 | 12.248 ms | 31.00% | 1.531 | board loop 扣除 START |
| STFT、ISTFT、配置與runtime外圍 | 0.887 ms | 2.25% | 0.111 | end-to-end 扣除 board loop |
| **總計** | **39.503 ms** | **100%** | **4.939** | 三筆、13,085-frame加權結果 |

目前 sustained throughput 為 25.896 frames/s。START 到退休的 P50／P95／max 為
26.281／27.701／42.968 ms；mailbox 的 P50／P95／max 為
16.855／17.359／31.222 ms。Mailbox 與 START latency 的相關係數約為 0.787，顯示
PS／Linux／MMIO 也是長尾延遲的重要來源。

### 2.3 稀疏度與運算量基線

- 956,096 個有效 matrix weights 中有 37,112 個零，結構性 weight sparsity 為
  3.8816%。
- 16 個 matrix roles 可使用 activation sparsity；4 個 first-layer roles 必須 dense。
- Dense matrix upper bound 為 2,136,128 MAC/frame。
- DeepFilter 為 576 complex MAC/frame，即 2,304 real multiplies 加 2,304 real adds。
- 現有 CSR 沒有 retired/skipped MAC 或實際 DDR read counter，因此不得用 boundary
  zero fraction 代替真正執行量。

### 2.4 Implementation 與功耗基線

| 項目 | 現有結果 |
| --- | ---: |
| LUT | 25,330 / 53,200（47.61%） |
| FF | 34,826 / 106,400（32.73%） |
| BRAM36 equivalent | 77.5 / 140（55.36%） |
| DSP48E1 | 46 / 220（20.91%） |
| Standard setup WNS | +0.263 ns |
| 250 ps setup-guardband WNS | +0.013 ns |
| Raw hold / 50 ps guardband hold | +0.064 / +0.014 ns |

PYNQ Linux 沒有暴露可用的 rail sensor。目前只有相同 routed checkpoint 的 Vivado
vector-less 估算：total on-chip 1.599 W、accelerator hierarchy 0.147 W、confidence
Medium。以估算功率乘實測時間得到約 63.17 mJ/end-to-end frame 與
3.876 mJ/accelerator active frame，但這不是實體儀器讀值。

## 3. 執行原則與證據分級

每次最佳化必須保留一個可重現的 before／after pair，且依下列層級清楚命名：

1. **Analytical estimate**：公式、payload與理論下限，不稱為板測結果。
2. **Host unit/reference**：Python／C reference與測試，不稱為RTL結果。
3. **RTL simulation**：XSim逐值、cycle與protocol證據，不稱為timing closure。
4. **Vivado implementation**：post-route timing、resource、DRC與CDC，不稱為板上RTF或功耗。
5. **Board measurement**：列明BIT、driver、輸入、測試次數和儀器後才可稱為實測。

每個完成的checkpoint都要：

- 只stage本次相關檔案；不得納入既有Vivado console／webtalk噪音。
- 執行對應測試並保存版本、命令、時間、SHA-256與結果。
- 建立描述性Git commit；若未來設定shared remote，再push該branch。
- 任何未量到的項目明確標示`UNKNOWN`或`BLOCKED`，不得以估值補成實測值。

## 4. Gate 1：增加逐階段profiling與硬體counter

### 4.1 PS runtime timestamp

每個frame保存至少以下時間點，clock一律使用同一個monotonic來源：

```text
T00 frame API entry
T01 frame/ownership precheck complete
T02 magnitude and fullband LayerNorm complete
T03 spectrum INT8 pack complete
T04 input/output buffer preparation and cache maintenance complete
T05 DMA descriptors submitted
T06 input MM2S and admission complete
T07 START accepted
T08 fullband result/mailbox ready
T09 64-byte mailbox read and FB release complete
T10 nine subband LayerNorm vectors complete
T11 784-byte mailbox write and SB commit complete
T12 output S2MM complete
T13 output invalidate/copy complete
T14 frame retirement and fault check complete
T15 dequantization/statistics complete
T16 ISTFT contribution complete
```

輸出逐frame raw timestamps或non-overlapping durations，另保存mean、standard deviation、
P50、P95、P99與max。Profiling overhead要以profiling on/off A/B量測；論文主效能數字使用
profiling關閉或證明其影響小於1%。

### 4.2 PL counters

控制CSR或debug snapshot至少新增：

- 每個global FSM state的累積cycles與visit count。
- 每個stage的load cycles、compute cycles與stall cycles。
- AXI AR bursts、R beats、R-channel idle/stall與stage bytes。
- Dense-eligible、active sources、weight requests、retired MAC與skipped MAC。
- Fullband、subband各branch/context與DeepFilter cycles。
- Mailbox WAIT_PS cycles、slot wait、claim/commit/release count與錯誤count。
- Input/output AXIS beats、backpressure cycles及DMA packet count。

Counter寬度要能支援至少一小時測試而不溢位，或定義明確的snapshot／wrap規則。讀counter
不得改變accelerator行為；reset與frame snapshot semantics必須在XSim驗證。

### 4.3 Gate 1 驗收

- Host tests及RTL self-checking regression通過。
- 所有non-overlapping timing buckets加總可在1%內重建總時間。
- Hardware state-cycle加總與frame cycle counter一致。
- Counter enable/disable不改變任何reference output。

## 5. Gate 2：PS mailbox、LayerNorm與控制路徑最佳化

這是最高優先級，因為現有mailbox平均16.742 ms，單獨已超過8 ms frame budget。

### 5.1 Mailbox bulk access

- 將16次Python 32-bit reads與196次Python 32-bit writes改成同一4 KiB device mapping的
  連續32-bit bulk access。
- 保留64-byte FB與782-byte SB加2-byte zero padding的ABI。
- 保留claim、commit、release、frame ID、slot ownership與ordering barrier。
- 以scalar Python MMIO作為reference模式；bulk模式必須逐byte相同且fail-closed行為一致。
- 分別量測payload copy、control event與barrier時間，不把PS LayerNorm混在單一數字內。

### 5.2 Native LayerNorm/runtime

- 建立ARM native C/C++核心，或可由PYNQ Python載入的受控native extension。
- 使用float32/NEON實作1次fullband和9次subband LayerNorm。
- 預先建立reflect-window索引與固定output offsets，避免每frame重複`pad`、
  `concatenate`、temporary allocation及parameter validation。
- 凍結round-to-nearest ties-to-even、clip `[-127, 127]`與epsilon語意。
- 每個代表性與隨機vector必須與現有NumPy reference逐值相同；若採近似算法，必須另立
  accuracy contract，重跑完整品質實驗，不可悄悄放寬bit-exact要求。

### 5.3 DMA、cache與buffer

- 預先配置並重用全部buffer。
- 驗證S2MM完整覆寫2,048 bytes後，是否能安全移除每frame output清零與pre-flush。
- MM2S只flush CPU實際更新的64 B與512 B；S2MM在CPU讀取前做必要invalidate。
- 將debug print、boundary sparsity與per-frame JSON組裝移出正式benchmark hot path。
- 比較polling、busy-poll與IRQ；記錄latency、P99與CPU／board power，不假定IRQ必然較快。
- 為input、spectrum與output建立雙buffer；若目前RTL只允許單frame in flight，要明確區分
  「CPU準備重疊」與「PL frame pipeline」，不可把前者誤稱為完整pipeline。

### 5.4 Gate 2 目標

| 項目 | 基線 | Gate 2工程目標 |
| --- | ---: | ---: |
| Mailbox service | 16.742 ms | 0.5–1.5 ms |
| START外board overhead | 12.248 ms | 1–2 ms |
| Mailbox P99 | 20.492 ms | ≤2 ms |
| Native／NumPy結果 | 既有reference | 全部逐值相同 |

這些是工程目標，不是尚未執行就能引用的論文結果。

## 6. Gate 3：PL parameter loading與compute最佳化

### 6.1 先量測再選路徑

現有每frame會處理12個stages，parameter transfer合計1,052,944 bytes。理想
64-bit/100 MHz zero-wait模型約需1.399 ms，但實際時間還含DDR latency、單outstanding、
stage barrier、compute與backpressure。必須用Gate 1 counter判斷主因後再選擇：

- DDR／AR stall主導：延長burst、允許多outstanding、stage prefetch。
- Cache replace主導：有限度ping-pong或保留hot stage/tile。
- PE compute主導：增加MAC lanes、改善serializer／requant bottleneck。
- Sparse request主導：active-source按需fetch、壓縮index或tile-aware cache。
- WAIT_PS主導：優先完成Gate 2，或採Gate 4的PL LayerNorm fallback。

### 6.2 候選最佳化

1. 將AXI read burst由最多16 beats提高到經BD／DDR驗證後的較長burst。
2. 加入2–4個outstanding reads與正確的ID／response accounting。
3. 在當前stage compute時prefetch下一stage；任何bank replacement必須等consumer release。
4. 評估使用剩餘BRAM保存最大或最常重載的stage，而不是複製整個1.053 MB image。
5. 使用剩餘DSP增加計算並行度；每次擴lane都先做PYNQ-Z1 Gate A資源估算。
6. 以真實active-source list減少eligible weight reads，mandatory dense first layers保持不變。
7. 保持100 MHz為第一目標；現有250 ps guardband後只有+0.013 ns，不先以升頻掩蓋架構問題。

### 6.3 資源與timing限制

- 所有主要資源必須低於80% review threshold。
- Full design standard setup、250 ps setup guardband、raw hold與50 ps hold guardband均需PASS。
- 無unrouted net、timing loop、clockless register、unconstrained internal endpoint或blocking DRC。
- 新counter、prefetch、cache或lane必須重跑CDC與reset/quiesce驗證。

### 6.4 Gate 3 目標

- START內非mailbox部分由9.626 ms降至4–5 ms。
- 完整平均frame initiation interval ≤6.4 ms，P99 ≤8 ms。
- Sustained throughput ≥125 frames/s；工程目標≥156.25 frames/s，提供20%餘裕。
- sparse與dense結果各自和matching oracle一致。

## 7. Gate 4：PL LayerNorm fallback

只有當native PS mailbox完成後仍無法達到RTF目標，才啟動此較大修改：

- INT32 mean／variance accumulation。
- 定點reciprocal square root LUT或Newton iteration。
- affine、rounding、saturation與INT8 requantization。
- magnitude／fullband projection buffering及9個context的固定window mapping。
- bit-exact或有明確誤差界限的reference、XSim、OOC與full-route證據。

此方案可以移除frame內PL→PS→PL dependency，但會增加RTL驗證、DSP／LUT、pipeline與
論文數值誤差分析成本。若啟用，PS版本仍保留作為ablation baseline。

## 8. 必須補齊的實驗矩陣

### 8.1 完整100組PTQ音訊品質

資料來源解析為`C:\Users\User\Desktop\project\PTQ資料數據`，包含100組
clean/noise/noisy matched triplets。每組保存：

- 輸入、clean reference、noise及enhanced output的SHA-256。
- 原始samples、實際評估samples、frames與對齊／截斷規則。
- Input與enhanced SNR、SI-SDR及改善量。
- STOI與PESQ；保存套件名稱、版本、sample-rate模式與失敗案例。
- clipping、DC offset、RMS與output saturation statistics。
- 每組mean/P95/P99/max frame latency、RTF、fault與final DMA state。

彙整平均值、median、standard deviation、95% confidence interval、最差案例及退步比例。
不可只報挑選後的三筆。若STOI/PESQ相依套件不可取得，該欄標示BLOCKED並保留可重現的
安裝需求，不以自行定義的替代分數冒名。

### 8.2 Correctness regression

- 至少保留現有33-frame bit-exact fixture。
- 從100組音訊分層抽樣低／中／高SNR及silence、clipping邊界frames，逐值比對所有
  256x2 INT32 accumulators。
- dense與sparse模式分開比對matching software oracle。
- 驗證frame ID wrap、first-frame clear state、跨frame recurrent state與DeepFilter history。

### 8.3 Performance ablation

固定相同BIT、parameter image與音訊，至少比較：

| 因子 | Levels |
| --- | --- |
| Mailbox I/O | scalar Python、bulk mapped、native |
| LayerNorm | NumPy float64 baseline、float32／NEON、PL fallback（若實作） |
| Wait方式 | sleep polling、busy-poll、IRQ |
| Cache維護 | conservative baseline、驗證後optimized |
| Diagnostics | on、off |
| Model execution | dense、sparse |
| Parameter path | baseline、long burst／outstanding／prefetch各checkpoint |

每個組合先warm-up，再至少重跑5次；報mean、P50、P95、P99、max、standard deviation和
95% confidence interval。主表採完整end-to-end RTF；另表列START latency、initiation
interval及各state cycle，避免把不同計時邊界混在一起。

### 8.4 Sparsity與computation

每frame／role保存：

- activation nonzero sources與總sources。
- eligible與mandatory dense roles。
- requested weight words／bytes。
- retired dense-equivalent、actual與skipped MAC。
- stage preload、on-demand reads及cache hit/miss。
- DeepFilter complex MAC與有效tap數。

論文至少要提供dense vs sparse的actual DDR bytes、MAC、latency與energy，不用weight zero
fraction或boundary zero fraction代替runtime savings。

### 8.5 實體功耗與能量

需要外接可校準的DC input power meter或shunt acquisition；目前板上Linux sensor不存在，
所以在儀器提供前此項維持BLOCKED。量測規格：

1. 保存儀器型號、校準／精度、sample rate、接線、輸入電壓與環境溫度。
2. 同一PS boot與BIT下量測idle、DMA-only、mailbox-only、dense inference、sparse inference。
3. 每個狀態warm-up後至少量測60秒並重跑5次。
4. 同步保存frame counter／GPIO marker或時間戳，使power trace能與active interval對齊。
5. 報告board input power、idle-subtracted dynamic power、energy/frame與energy/audio-second。
6. Vivado vector-less estimate獨立列出，不和physical measurement平均或混用。

計算定義：

```text
gross_energy_per_frame = integral(board_input_power dt) / completed_frames
incremental_energy_per_frame = integral((active_power - idle_power) dt) / completed_frames
energy_per_audio_second = total_active_energy / evaluated_audio_seconds
```

若使用wall／USB meter而無法可靠同步到frame，只能報長時間平均board power與依completed
frames換算的能量，不宣稱cycle-level power。

### 8.6 長時間穩定性與錯誤恢復

- 連續至少1小時或450,000 frames的real-time／最快速循環，取較嚴格者。
- 每frame ID連續；所有DMA、mailbox、control與accelerator fault為0。
- 執行受控input starvation、output backpressure、timeout及abort recovery。
- 驗證DMA先Halted+Idle、quiesce proof、一次soft reset、epoch遞增與重新inference。
- 不在DMA enabled時重複JTAG重配PL。
- 保存kernel log、driver log、溫度（若可取得）、開始／結束狀態與所有錯誤注入結果。

### 8.7 Final implementation

任何RTL變更後都要從clean project重跑：

- Control／mailbox／FSM／PE／memory／DeepFilter XSim。
- Host Python／native unit tests及reference tests。
- PYNQ-Z1 BD validation與global synthesis。
- opt、place、physical optimization、route及post-route physical optimization。
- Standard與guardbanded setup／hold、utilization、clock、CDC、DRC、methodology與power。
- 從同一routed checkpoint產生matching BIT/HWH與SHA-256 manifest。
- 只有上述gate全部通過才燒錄板子並產生新的board evidence。

## 9. 論文表格、圖與artifact

最終至少產生：

1. 系統PS–PL資料流圖，標出payload、numeric format與ownership。
2. Before／after latency breakdown stacked chart。
3. Dense／sparse per-state cycle及DDR bytes圖。
4. 100組音訊的SNR、SI-SDR、STOI、PESQ分布與退步案例。
5. RTF／quality／resource／energy trade-off表。
6. FPGA resource與post-route timing表。
7. Board power idle／dense／sparse trace與energy/frame表。
8. Mailbox、native runtime、parameter loader、parallelism的逐項ablation表。
9. 與ARM-only或可重現software baseline的相同輸入比較。
10. Limitations：資料集規模、PYNQ-Z1、16 kHz、vector-less estimate與未涵蓋的泛化範圍。

建議將新證據集中在：

```text
rtl/reports/accelerator_optimization_final/
  baseline/
  profiling/
  mailbox_ablation/
  parameter_ablation/
  board_100_audio/
  power_physical/
  endurance/
  implementation/
  paper_tables/
  summary.md
  evaluation.json
  SHA256SUMS
```

大批enhanced WAV若不適合直接進Git，至少保存輸入／輸出SHA、生成命令、metrics與可重建
路徑；代表性音訊與論文實際引用案例則保留。原始PTQ檔案永遠不覆寫。

## 10. 最終驗收標準

### 10.1 必須通過

- 完整100組音訊成功，沒有未解釋的DMA／mailbox／control fault。
- Hardware與matching quantized reference通過既定bit-exact contract。
- Sustained end-to-end RTF ≤1.0；工程目標≤0.8。
- 平均frame initiation interval≤6.4 ms，P99≤8 ms。
- 至少1小時穩定性及一次完整soft-reset recovery PASS。
- Full-design standard與guardbanded setup／hold、route、CDC及blocking DRC PASS。
- 所有主要資源低於80% review threshold。
- 完成physical board power；若儀器仍缺少，論文只能明列功耗實驗BLOCKED，不能用Vivado
  estimate宣稱實測能效。
- 每個表格數值都能回溯到JSON／log／report、版本與SHA-256。

### 10.2 Paper-ready完成定義

只有下列項目同時存在才標為paper-ready：

1. 凍結的source、BIT/HWH、parameter與software release manifest。
2. 100組品質結果與統計分析。
3. 完整latency、RTF與ablation結果。
4. Actual sparsity、MAC與DDR traffic counters。
5. Physical power／energy結果或誠實縮小論文claim。
6. 長時間穩定性和recovery結果。
7. Post-route timing/resource證據。
8. 可直接使用於論文的表格、圖、方法與limitations文字。

## 11. 建議時程與決策點

| 時間 | 工作 | Go／No-Go條件 |
| --- | --- | --- |
| Day 1 | PS timestamps、RTL counter設計與host tests | bucket可重建總時間 |
| Day 2–4 | Bulk/native mailbox、LayerNorm、DMA/cache優化 | mailbox≤1.5 ms且bit-exact |
| Day 5 | 實板A/B與第一次RTF判定 | 若PL active仍>8 ms，進Gate 3 |
| Day 5–8 | Parameter loader、prefetch與必要PE並行化 | mean≤6.4 ms、P99≤8 ms |
| Day 9–10 | 100組品質、dense/sparse與長序列 | fault=0、品質無未解釋回歸 |
| Day 10–11 | Physical power與energy | 儀器證據完整 |
| Day 11–14 | 論文圖表、統計、artifact與final report | 全部數字可追溯 |

若Day 5後native PS方案仍無法讓pipeline接近RTF 1，再決定是否投入PL LayerNorm；此fallback
通常使總時程增加1–2週。若physical meter尚未提供，其他工作照常完成，但能耗claim維持
blocked而不偽造結果。

## 12. 目前最重要的判斷

- 不應優先升頻：現有setup guardband太薄。
- 不應只優化sparsity：weight sparsity僅3.882%，且mailbox與固定stage成本主導RTF。
- 不應只移除mailbox：即使mailbox時間理想化為0，現有其餘路徑仍約22.76 ms/frame。
- 最短論文路徑是：**完整profiling → native/bulk PS路徑 → 依counter最佳化PL →
  100組與physical power → ablation與論文artifact**。
- 若無法達到RTF≤1，仍可誠實投稿為功能部署與瓶頸研究，但不得使用real-time或高能效主張；
  若要形成更強的系統論文，real-time、actual sparse counters與physical power是三個核心gate。
