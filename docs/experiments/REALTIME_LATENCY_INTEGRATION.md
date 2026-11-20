# Real-time latency integration record

日期：2026-09-09（Asia/Taipei）

## 判定標準

16 kHz、hop 128 的輸入每 8 ms 產生一個 frame。Real-time gate 要求 PL p99
低於 8 ms，且 sustained board-loop 與 end-to-end RTF 都低於 1.0；希望保留
RTF 不高於 0.8 的餘裕。Pipeline 的單幀 wall latency 可高於 8 ms，但 steady-state
每 8 ms 必須至少退休一幀。

## 階段結果

| Phase | 改變 | 證據 | PL/frame | board RTF | E2E RTF | 結果 |
|---:|---|---|---:|---:|---:|---|
| 0 | ec457b1，16 PE，100 MHz，64-bit | 五檔 PYNQ 實測 | 11.062 ms mean | 2.694 | 2.807 | FAIL |
| 1 | Q12/Q20 LayerNorm 整數 contract | 33 個保存 frame host 重算 | N/A | N/A | N/A | numeric PASS |
| 2 | 共用 Q12 LayerNorm leaf，125 MHz | 6-vector bit-exact XSim + OOC route | N/A | N/A | N/A | leaf PASS；integration pending |
| 2b | model-specific parameter ROM/maps | 全 362 組參數 + invalid-index XSim、OOC route | N/A | N/A | N/A | parameter gate PASS |
| 3 | magnitude-to-subbands coordinator，125 MHz | 3 組 scaled fixture、bit-exact XSim + OOC route | 0.183 ms component | N/A | N/A | coordinator PASS；top/board pending |
| 4 | production PL LayerNorm frontend，16 PE，100 MHz | coordinator→dispatcher + production-top XSim；OOC route | 0.23037 ms component upper sample | N/A | N/A | functional PASS；OOC setup −0.015 ns |
| 4a | PE fault internal-control register cut，16 PE，100 MHz | 12,450,567-check sparse XSim + production-top XSim + OOC route | normal path +0 cycles | N/A | N/A | OOC timing PASS；WNS +0.006 ns |
| 4b | non-fallthrough job launch register slice，16 PE，100 MHz | 12,450,755-check sparse XSim + production-top XSim + OOC route | ≤+0.00030 ms/frame | N/A | N/A | OOC PASS；WNS +0.064 ns；high congestion |
| 4c | 8-bank parameter-write locality，16 PE，100 MHz | 13 structural assertions + 12,450,755-check sparse XSim + production-top XSim + OOC route | normal path +0 cycles | N/A | N/A | OOC PASS；WNS +0.335 ns |
| 4d | isolated 102/104 MHz clock sweep，16 PE | checkpoint sensitivity + fresh OOC synth/route/DRC | frontend 0.22585/0.22150 ms | N/A | N/A | 102 preferred；104 ceiling PASS |
| 5-contract | production-v2 32-PE interface/packing review | frozen baseline + controller/memory contract audit | 8.07793/7.95573/7.83823 ms @100/102/104 analytical | N/A | N/A | contract approved；Phase 5A complete |
| 5A | production-v2 independent 32-lane Hybrid MAC array | 33,280-check XSim + fresh 100/102 MHz OOC route | 1 cycle/command，II=1；frame N/A | N/A | N/A | component PASS；100/102 WNS +4.118/+3.888 ns |

Phase 0 固定使用 file IDs `000/025/050/075/099`，共 23,137 frames、
185.056 s audio。每個可上板的新階段都必須使用同一組輸入重新量測，不可用
分析估算填入實測欄位。

## Phase 1：LayerNorm 數值格式

PL contract 採用：

- magnitude、fullband projection dequantized value、gamma、beta：signed Q12；
- population variance：Q24；
- inverse standard deviation 與 output scale reciprocal：Q20；
- epsilon：`168 / 2^24`，對應 float `1e-5`；
- 所有除法與右移：round-to-nearest、ties-to-even；
- 最終輸出飽和到 `[-127, 127]` INT8。

使用真實參數與保存的 33 個 real frames 比較目前 float 路徑：fullband
99.7159% bytes 完全一致，subband 99.3800% 完全一致，兩者最大差異均為
1 INT8 LSB。這只證明數值格式可進 RTL，不是音質、synthesis 或板測完成。

五檔 magnitude 的觀察最大值是 7.9391，仍在 signed Q12 的正值上限
7.9998 內。正式 ingress 必須 fail closed 檢查溢位；不能靜默 wrap。

## Phase 2：共用 LayerNorm leaf

`layernorm_engine_q12` 支援長度 2 到 158，依序完成 mean、population
variance、integer square root、reciprocal、affine 與 INT8 saturation。6 組
edge/代表性長度向量在隨機 input bubble 與 output backpressure 下，皆與 frozen
integer oracle bit-exact：

| 長度 | XSim cycles | 125 MHz latency |
|---:|---:|---:|
| 2 | 286 | 2.288 us |
| 8 | 427 | 3.416 us |
| 46 | 1,346 | 10.768 us |
| 64 | 1,788 | 14.304 us |
| 94 | 2,517 | 20.136 us |
| 158 | 4,043 | 32.344 us |

Production 每個 frame 的 10 個 vector 總長為 846。以 testbench 的保守上界
`25*N + 280` cycles/vector 計算，單一 shared engine 為 23,950 cycles，約
0.1916 ms @ 125 MHz 或 0.2395 ms @ 100 MHz。這是 XSim-derived bound，尚未
包含 production coordinator、memory arbitration 或板端軟體成本。

125 MHz OOC place-and-route 結果為 WNS +0.144 ns、internal register-to-register
WHS +0.050 ns、0 routing error；使用 1,559 LUT、1,106 FF、6 DSP、0 BRAM。
all-path WHS -1.202 ns 來自 OOC I/O path，不能當成完整系統 hold closure；仍須
在 Zynq block design 重新確認完整 timing coverage、WNS/WHS 與 DRC。

為達成正 setup slack，逐步改善的 post-route WNS 為：sync LUTRAM/registered
multipliers -7.233 ns、divider finish split -5.655 ns、fixed narrow rounding
-2.900 ns、divider/sqrt round split -0.426 ns、centered registers -0.383 ns、
affine/range split +0.144 ns。最早 async-array 版本的 -18.282 ns 是人工停止的
診斷迭代，不是完整 implementation gate。

## Phase 2b：模型參數與索引 ROM

從 checksum-verified frozen parameter archive 產生 362 組 signed-Q12
gamma/beta、4 組 reciprocal、255-entry fullband projection dequantization map
與 782-entry subband source-index map。XSim 檢查全部 362 組參數、4 組非法索引
與隨機 output backpressure；125 MHz OOC route 為 WNS +2.542 ns、internal WHS
+0.102 ns、0 routing error，使用 293 LUT、29 FF、0 BRAM。

## Phase 3：connected magnitude-to-subbands coordinator

Coordinator 接收 512-byte signed-Q12 magnitude（64-bit AXIS、每 beat 4 bins），
以同一顆 LayerNorm engine 產生 64-byte normalized fullband，擷取 64-byte
fullband projection，組合並正規化 9 個 subband vectors，最後存入本地
782-byte buffer 直接供 dispatcher 型態的 read handshake 使用。

三組 connected arithmetic fixtures（保存 frame 0/16/32 的 magnitude 分別縮放到
最大 7.5，projection 獨立注入）在 ingress/projection gap 與 output/read
backpressure 下逐 byte 驗證 64-byte fullband 及 782-byte subbands，全數 bit-exact。
每組從第一個 magnitude beat 到 `subbands_valid` 為 22,875 cycles，即 0.22875 ms
@ 100 MHz 或 0.18300 ms @ 125 MHz。這是 component XSim latency，不含
fullband PE projection 的等待、production top、DMA 或板端軟體。

OOC place-and-route 結果：

| Clock | WNS | internal WHS | route errors | LUT | FF | DSP | BRAM18 |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 MHz | +0.871 ns | +0.052 ns | 0 | 2,491 | 1,288 | 6 | 1 |
| 125 MHz | +0.399 ns | +0.051 ns | 0 | 2,491 | 1,288 | 6 | 1 |

兩個 OOC run 的 all-path WHS 仍受未放置外部 pin 影響而為負；完整 Zynq block
design 必須重新關閉 WNS/WHS、timing coverage、routing 與 DRC，才能產生 BIT/HWH。
scaled fixtures 也不是五檔原始 audio 的 end-to-end model 證據；五檔板測欄位維持
`NOT_MEASURED`。

## Phase 4：production top PL LayerNorm frontend

`accelerator_top` 預設改為 `USE_PL_LAYERNORM=1`：第一個 64-bit AXIS ingress
接收 512-byte signed-Q12 magnitude，coordinator 產生 normalized fullband 並直接
串接 production dispatcher；fullband projection 回送 coordinator 後，九個 subband
vectors 在 PL 完成並由本地 782-byte buffer 供 dispatcher 讀取。舊 mailbox 路徑仍可
用 `USE_PL_LAYERNORM=0` 明確啟用，外部 Zynq HP/AXIS 寬度維持原生 64 bit。

Host 端新增 little-endian Q12 packer，直接 assertions 通過 512-byte shape、ties-to-even、
最大值、negative、NaN、Inf 與 overflow fail-closed；六個修改後 Python 檔通過
`py_compile`。目前測試主機沒有 pytest，因此不能把完整 pytest suite 列為本階段 PASS。

三組 coordinator→production dispatcher connected XSim 各檢查 64 fullband + 782
subband feature reads，跨 frame 全部 byte-exact；從第一個 magnitude beat 到
`subbands_valid` 為 23,036、23,037、23,037 cycles，即最多 0.23037 ms @100 MHz
或 0.184296 ms @125 MHz。此數字包含 testbench 的 64 次 dispatcher fullband read，
但不含真實 fullband PE projection compute、其餘 accelerator、DMA 或 software。
production-top 既有 XSim/elaboration 亦全部通過。

100 MHz OOC post-route 為 WNS -0.015 ns、WHS +0.007 ns，routing error 為 0，
timing coverage checks clean；使用 21,144 LUT、28,596 FF、71 RAMB36、4 RAMB18、
52 DSP。Setup critical path 位於 frozen 16-PE 的 membrane fault 經 shared requant 到
serializer enable，並非 LayerNorm coordinator。因 WNS 仍為負，本階段不可產生或上板
BIT/HWH，五檔 board latency 保持 `NOT_MEASURED`。

## Phase 4a：PE fault internal-control timing cut

保留 public `reset_required`/`pe_fault` 的 same-cycle 診斷，並在 PE overflow/protocol
fault 進入 subsystem 內部 control/ready network 前使用既有 fault registers。若 fault
與完成同週期，`fb_done`/`sb_done` 會被 public immediate fault 抑制；偵測 edge 上最多
只允許既有已接受交易退休，下一週期進入 sticky fail-closed，之後必須 coordinated
reset。正常資料路徑沒有新增 cycle，因此本階段的直接 frame latency delta 是 0。

11 個 CP6 結構 assertions、完整 sparse connected XSim 的 12,450,567 checks，以及
production-top XSim 全部通過。100 MHz OOC synthesis WNS 由 Phase 4 的 -0.419 ns
改善為 -0.077 ns；post-route WNS 由 -0.015 ns 改善為 +0.006 ns，WHS +0.013 ns，
routing/coverage checks clean。post-route 使用 21,267 LUT、28,574 FF、71 RAMB36、
4 RAMB18、52 DSP，資源低於 80%。新的 critical path 是 global FSM fullband launch
到 sparse job-controller row-tile enable，不再是 PE fault/shared-requant/serializer。

這只完成 `accelerator_top` OOC 100 MHz timing gate，餘裕仍只有 0.006 ns；不是完整
Zynq block-design closure，也沒有 matching BIT/HWH，所以五檔 board latency 仍為
`NOT_MEASURED`。下一步先對 job launch boundary 做 handshake register slice，再評估
105/110 MHz，不能從本次結果宣稱已可穩定升頻。

## Phase 4b：job launch register slice

在 global FSM 與 sparse job controller 間加入一個 non-fallthrough request register，
一次鎖住 fullband/subband identity、stage、branch 與 context。FSM 原本就會持續握住
start 直到 ready，因此外部 ready/valid contract 不變。Controller 只看暫存後欄位，
切斷 Phase 4a 的 FSM launch 到 row-tile enable 組合路徑。

每個 model frame 固定 30 個 PE jobs，因此保守正常路徑成本是 30 cycles，也就是
0.00030 ms @100 MHz。完整 connected regression 內的四個 frame 相較 Phase 4a 總共
增加 94 cycles；check 數因每-cycle safety assertions 增加到 12,450,755，但 dense
bytes 2,101,088、sparse bytes 1,052,208 與 30/60 job counters 均不變。12 個結構
assertions、connected sparse XSim 與 production-top XSim 全部通過。

100 MHz OOC synthesis WNS 從 Phase 4a 的 -0.077 ns 改善到 +0.740 ns；post-route
WNS +0.064 ns、WHS +0.012 ns，routing/coverage checks clean，使用 21,386 LUT、
28,469 FF、71 RAMB36、4 RAMB18、52 DSP。Route 花 48:50 且經多輪 congestion
recovery；新 critical path 是 64-bit parameter-write register 到 5,824-bit parameter
buffer，94.7% 為 routing。這筆結果仍不足以直接宣稱 105 MHz，下一步先把 parameter
write data 複製成低 fanout locality banks，再做頻率 sweep。

本階段仍只是 `accelerator_top` OOC；沒有完整 Zynq block-design closure、matching
BIT/HWH 或五檔 board measurement。

## Phase 4c：parameter-write locality banks

保留原本 registered one-hot commit cycle，但將單一 64-bit parameter-write data
register 複製成 8 組有 `keep` 屬性的 locality banks。每組最多只驅動 12 個
parameter-buffer words，取代單一 register 驅動 91 words 的 90-fanout routed path。
這個改動不增加 state、AXI beat 或正常 frame cycle，因此直接 latency delta 為
0 cycles；成本是相較 Phase 4b 增加 488 post-route FF。

13 個結構 assertions、connected sparse XSim 的 12,450,755 checks，以及
production-top XSim 全部通過；dense bytes 2,101,088、sparse bytes 1,052,208 不變。
100 MHz OOC synthesis WNS +0.410 ns；post-route WNS +0.335 ns、WHS +0.017 ns，
routing/coverage checks clean，使用 21,408 LUT、28,957 FF、71 RAMB36、4 RAMB18、
52 DSP。Parameter-write path 已退出前十名，route-design elapsed 從 Phase 4b 的
48:50 降到 1:43；新的最差路徑在 sparse job controller state 到 error-code enable。

這是 timing-enablement 與 implementation-runtime 改善，不是新的 board latency
數字；本階段仍沒有完整 Zynq block-design closure、matching BIT/HWH 或五檔板測。

## Phase 4d：clock frequency sweep

先用 Phase 4c 的 100 MHz routed checkpoint 做只讀 period sensitivity：102、103、
104、105、111.111、125 MHz 的 WNS 分別為 +0.139、+0.044、-0.050、-0.141、
-0.665、-1.665 ns。這只是同一 placement 的 candidate screening，不是 fresh route。

選定 102 MHz（9.804 ns）及邊界 104 MHz（9.615 ns）各自從 RTL fresh synthesis、
place、route。102 MHz 為 post-synth WNS +0.214 ns、post-route WNS +0.232 ns、
WHS +0.007 ns；104 MHz 為 +0.025 ns、+0.032 ns、WHS +0.021 ns。兩者皆為 0
routing/DRC error、timing coverage clean、資源低於 80%。104 MHz 的新 critical
path 是 sparse-memory-service state 到 job-controller state，data path 9.313 ns，
69.5% 為 routing。

RTL/cycle count 不變；23,037-cycle frontend component 從 100 MHz 的 0.230370 ms
降為 102 MHz 的 0.225855 ms（-1.96%）或 104 MHz 的 0.221501 ms（-3.85%）。
這仍不含真實 PE projection、其餘 accelerator、DMA、software 與 board interaction。
工程候選採 102 MHz，因 routed setup margin 為 +0.232 ns；104 MHz 只記為 OOC
探索上限，不能當 production recommendation。Exact PS/FCLK 或 MMCM 產生、完整
Zynq timing 與五檔 board latency 均尚未驗證。

## Phase 5 contract：production-v2 32 PE

32 PE 會改變 frozen v1 明定的 16-lane physical array、membrane/collector、serializer、
CDF group 與 16-row memory tile，因此不是把一個 parameter 從 16 改成 32。已完成
mandatory PE baseline/manifest/handoff review，確認必須建立獨立 `production_v2`，不得
修改 `rtl/pe_array/baseline/v1`。

介面與資料格式的主要變更是：PE operand/weight/state tile 從 128 變成 256 bit，
accumulator/direct-value 從 512 變成 1,024 bit，lane mask 從 16 變成 32，index 從
`tile*16+lane` 改成 `tile*32+lane`。Stage 0..11 的 row-tile count 由
`20,20,4,14,14,5,14,14,12,14,14,8` 改成
`10,10,2,7,7,3,7,7,6,7,7,4`。GSU parameter record 由 5,792 bit/91 個
64-bit words 改成 11,584 bit/181 words；projection record 由 1,120 bit/18 words
改成 2,240 bit/35 words。這需要新的 image-v5 generator/map、memory response、
job controller、membrane、collector、serializer、CDF 與 integration wrapper。

第一個已批准並完成的正式 checkpoint 只建立
`production_v2/rtl/pe/pe_hybrid_mac_array_32.v`：每 lane 獨立 clear/enable/mode，
完全重用 frozen Hybrid MAC 算術，不加入 controller、memory、RQ 或 serializer。
既有 feasibility bank 的 clear/enable/mode 是 32 lanes 共用，不能直接作為 production
替代品。完整介面與逐模組 gate 記錄於
`team_workspace/decisions/2026-09-09-production-v2-32pe-contract.md`。

Phase 5 contract 本身沒有新增 RTL，直接 latency delta 為 0。Phase 5A 新增正式的
32-lane structural array；XSim 在 1,040 cycles 內通過 27,881 accepted commands 與
33,280 lane checks，command-to-accumulate latency 為 1 cycle、II=1。100/102 MHz 的
fresh OOC route 均通過 component gates，WNS 分別 +4.118/+3.888 ns，internal WHS
均 +0.051 ns，資源為 3,743 LUT、2,176 FF、32 DSP、0 BRAM。OOC all-path WHS
-1.226 ns 是沒有 physical partition-pin location 的 top-level input boundary path，
不是 full-system hold 結果。

Phase 5A 尚未連接 controller、memory、membrane、serializer、full-Zynq 或 DMA，
因此 frame latency 與五檔板測仍是 `NOT_MEASURED`。使用舊 file081 profile 的 bounded analytical model，假設 70% compute
可因 16→32 lanes 減半、ARM `wait_ps` wall time 不變，可得 8.077932 ms@100 MHz、
7.955733 ms@102 MHz、7.838234 ms@104 MHz、6.831504 ms@125 MHz。102 MHz 只讓
mean 剛低於 8 ms，沒有 p99 餘裕；104 MHz 又只有 +0.032 ns OOC setup margin，125 MHz
未 timing-close。因此真正 real time 仍須合併 PL LayerNorm/no-mailbox、32 PE、內部
256-bit feed/prefetch 與 persistent overlapped DMA，再由同五檔實板量測確認。

## 最終 100 檔驗收

開發中的每個 board-capable checkpoint 仍先使用固定 file IDs
`000/025/050/075/099`，確保修改效果可快速歸因。最終 PL LayerNorm、production-v2
32 PE、內部 256-bit feeding、clock 與 persistent/overlapped DMA 全部整合，且完整
Zynq block design 的 WNS/WHS、timing coverage、routing 與 DRC 通過後，再使用與
`ec457b1` 相同 input triplet/hashes 的 `000..099` corpus 做 final A/B。

先前 100 檔基線為 426,196 frames、3,408.768 s evaluated audio，weighted mean frame
11.055 ms，aggregate frame/board/E2E RTF 1.382/2.739/2.853，mean SNR/SI-SDR
improvement +7.688/+7.454 dB；file081 的獨立 PL profile mean/p95/p99 是
10.484/11.411/12.282 ms。

新版本採兩個互不混用的 pass：100 檔 profiling-off 作為 primary throughput/audio
結果；固定五檔加 file081 開 coherent hardware profile，統計 PL LayerNorm、global
state、stage 0..11 load/compute/stall、serializer/shared-RQ、CDF/output、AXI wait/
backpressure 與 software/DMA interaction。硬體 profiler schema 必須為 32 PE 升版，
不能繼續用 `dense_equivalent_requests * 16` 計算 MAC。完整欄位、資源/timing 表、
輸出檔案與安全 reset/DMA gate 定義於
`team_workspace/decisions/2026-09-09-final-100-audio-validation.md`。

## Phase 5B：image-v5 32-row packing

經明確批准後，已新增獨立 `generate_memory_v5.py` 與 versioned v5 artifacts；沒有修改
v3/v4 generator/artifacts，也沒有接到 production controller。Weight/state tile 為
256 bit/32 rows；GSU parameter record 為 11,584 bit、1,448 bytes、181 個 64-bit
words，projection record 為 2,240 bit、280 bytes、35 words，兩者都不再有 record
padding。Stage 0..11 row tiles 已固定為 `10,10,2,7,7,3,7,7,6,7,7,4`。

獨立 integer oracle 7/7 PASS：逐一核對 current raw tensor 的所有 weight lane 與
35,120 個 parameter values，檢查 duplicated GSU halves、final padding zero，並證明
每個 v5 tile/field 都等於對應兩個 v4 tiles/fields。Global sigmoid 2,040 bytes 維持
原 frozen ordering/hash；Vivado 2018.3 `xvlog` 也接受 generated stage/readback tables。
Image 為 1,056,224 bytes，SHA-256 是
`0a898aca19599f976b3988f92ff645b1490dc3ac470003683199e80b134f458a`。

Exact weight-tile requests 從 59,756 降到 29,990（-49.81%），parameter records 從
153 降到 77（-49.67%）；但 external PS7 HP/AXIS 仍是 64 bit，每個 256-bit tile
仍需四個 bus words。因 Phase 5B 尚未接 controller/memory，direct cycle delta 為 0，
frame/board latency 是 `NOT_MEASURED`，LUT/FF/DSP/BRAM 是 `NOT_APPLICABLE`，不能把
request count 直接當成實測加速。

## 下一個 gate

Phase 5B 已交付並停止。下一個 gate 是 Phase 5C 32-row memory-service response 與
job-controller providers，等待明確批准。之後才依序進入 membrane/serializer/CDF、
connected top、full-Zynq timing、BIT/HWH 與五檔板測；一百檔仍只在最終候選完整通過
所有 gate 後執行。

完整機器可讀紀錄：
`rtl/reports/realtime_latency/latency_ledger.json`。
