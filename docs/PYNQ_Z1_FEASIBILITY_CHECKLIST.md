# PYNQ-Z1 模塊可行性檢查表

本檢查表是所有新 RTL、PS software、memory/AXI 與整合模塊的必要設計 gate。
目的不是只證明單一 testbench 正確，而是避免完成後才發現完整配置無法放入
PYNQ-Z1、無法達到吞吐量，或被 DDR/PS transfer 限制。

## 固定規劃基準

| 項目 | 規劃基準 |
| --- | --- |
| FPGA part | `xc7z020clg400-1`（PYNQ-Z1） |
| PL resources | 53,200 LUT、106,400 FF、140 BRAM36、220 DSP48E1 |
| 起始 PL/AXI clock | 100 MHz；若模塊採 200 MHz，必須另外說明 clock domain 與 CDC |
| External PS/PL ingress/egress | 64-bit AXI4-Stream + Xilinx AXI DMA 起始配置 |
| PS LayerNorm intermediate | 4 KiB dual-slot PL BRAM mailbox；PS `M_AXI_GP` + AXI BRAM Controller，繞過DDR controller |
| Control | 32-bit AXI4-Lite |
| Main weight storage | PS DDR；PL 只放 stage/tile cache、state、FIFO 與必要 lookup table |
| 數值基準 | INT8 weight/activation/state、INT32 accumulator；例外須在隨 commit 保存的設計證據中說明 |

上述資源數是 device capacity，不是可全部分配給運算陣列的預算。AXI/DMA、FSM、
CDC、debug、routing 與 timing closure 都需要空間。任何單項預估超過 device 的
80% 都標成 high risk，必須提出減少 lanes、time-multiplex、tiling 或移到 PS 的
替代方案；80% 是 review trigger，不是宣稱 implementation 一定成功的保證線。

## Gate A：寫 RTL 前

新增或改變硬體/PS datapath 前，先確認下列評估，並把適用的結論記錄在會隨
commit 保存的設計文件或實作說明中；不需要另建 task card：

```markdown
## PYNQ-Z1 feasibility

- Placement: PC/host | PS CPU | PL RTL
- Target part / clock:
- Numeric formats and vector/tensor shapes:
- Parallel instances / lanes:
- Estimated LUT / FF / DSP / BRAM per instance:
- Scaled total at the intended instance count:
- Local buffer and state bytes, ports, banking:
- GP-mapped mailbox bytes, slots, MMIO transactions/frame, and ordering:
- DDR bytes per frame/audio and required sustained bandwidth:
- External AXIS payload, packet count, DMA/cache-maintenance frequency:
- PS LayerNorm/MMIO/IRQ or polling latency assumptions:
- Estimated cycles/frame, initiation interval, and RTF contribution:
- Clock domains / CDC:
- Resource or bandwidth hot spot:
- Fallback if the estimate does not fit:
- Evidence level: repository fact | analytical assumption | measured result
- Feasibility: PASS | PASS WITH RISKS | BLOCKED | UNKNOWN
```

`UNKNOWN` 可以開始探索性 proof-of-concept，但不能宣稱可整合或可上板。若沒有
instance-scaled total，只量到「一個 lane」的資源，也維持 `UNKNOWN`。

## Gate B：模塊行為完成後

最低驗收要求：

1. Self-checking testbench 覆蓋正常、邊界、reset 與 backpressure/error cases。
2. 記錄 latency、initiation interval、有效 throughput 與實際 packet/read 次數。
3. 用預定 instance count 更新 scaled resource 與 memory-port 需求。
4. 對 multiplier、BRAM、多 lane、AXI、寬 datapath 或高 fanout 模塊，在 Vivado
   可用時以 `xc7z020clg400-1` 執行代表性 OOC synthesis。
5. 報告 actual LUT/FF/DSP/BRAM 與 timing slack；OOC 結果不能替代完整
   implementation，也不能直接外推為板上 Fmax。
6. 若 scaled estimate、memory ports、DDR bandwidth 或 timing 不可接受，先調整
   lanes、pipeline、banking 或 PS/PL partition，再進入整合。

## Gate C：整合前與整合後

- 整合前要把各模塊的資源相加，另外列出 AXI interconnect/DMA、FSM、FIFO、
  clock/reset 與保留 margin；不可只引用最漂亮的單模塊 report。
- Full-system synthesis 後以 `report_utilization` 與 `report_timing_summary` 取代
  analytical numbers。
- Implementation 完成後記錄 post-route WNS/TNS、clock utilization、congestion
  與 BRAM/DSP placement。
- 實際PYNQ-Z1上板後，才可記錄parameter/DMA bandwidth、GP mailbox MMIO與PS
  preprocessing latency、PL cycles、end-to-end RTF、功耗與音訊品質。

## 報告用語

| 證據 | 可以寫 | 不可以寫 |
| --- | --- | --- |
| 分析估算 | 「預估可行／high risk，假設為……」 | 「板子放得下」「達成 real time」 |
| RTL/XSim | 「行為與 reference 一致」 | 「timing 通過」「資源足夠」 |
| OOC synthesis | 「單模塊在指定 constraint 下的 synth timing/resource」 | 「完整設計可 route」「板上 200 MHz」 |
| Full implementation | 「完整 design post-route timing/resource」 | 「實際 RTF/功耗」 |
| Board measurement | 「在列明 bitstream/driver/input 下的實測值」 | 未列測試條件的泛化結論 |

## 現有風險提醒

- 完整 model parameters 大於 PYNQ-Z1 PL BRAM 容量；weight path 必須依靠 PS
  DDR 與 stage/tile cache，不能把全部 weights 推論成可常駐 BRAM。
- `pe_requant_lane` 的單 lane OOC 結果已達 200 MHz；完整PS7/AXI/DMA/memory/top
  已在100 MHz full implementation通過standard setup與50 ps hold guardband，結果為
  standard setup WNS `+0.263 ns`、250 ps setup engineering guardband WNS `+0.013 ns`、
  guardbanded hold WHS `+0.014 ns`、raw hold margin `+0.064 ns`。固定setup/hold、route、
  coverage、CDC、blocking DRC及資源gate均PASS，matching BIT/HWH已產生並燒錄到具名
  PYNQ-Z1 JTAG endpoint；33-frame實板輸出與integer oracle逐值一致，但mean frame
  latency為30.030 ms，相對8 ms hop的RTF約3.754。其後三筆PTQ資料完成13,085個連續
  sparse frames，weighted mean frame 26.368 ms、board-loop RTF 4.828，三筆SNR均改善，
  但同樣不可宣稱real time或200 MHz。
- Software soft reset只重置custom accelerator data plane；DMA、mailbox AXI controller
  與HP interconnect維持在system reset domain。RTL以persistent quiesce fence及兩拍registered
  safe proof阻止不安全reset，host helper先停止三個DMA channel並確認Halted+Idle。
  DDR DMA、cache flush/invalidate、mailbox ordering與13,118個累計frame traffic已上板
  PASS；最後frame退休後三個DMA status皆為`0x00000002`（Idle、無error）。診斷確認
  DMA仍enabled時不得
  直接重複JTAG重配PL，否則PS/HP transaction state可能不同步；正式程序須clean PS boot
  後只program一次。soft-reset fault recovery與長時間reset壓力仍是未完成gate。
- Subband preprocessing的raw payload不大；目前每frame PL->PS->PL dependency改走
  GP-mapped 4 KiB mailbox而不經DDR/DMA，但64-byte MMIO read、782-byte MMIO write、
  ordering barrier與PS LayerNorm已在PYNQ 3.0.1上追加連續量測13,085 frames，weighted
  mean mailbox service為16.742 ms且ownership／frame sequence無錯；mailbox目前是
  real-time throughput的主要已知組成。IRQ取代polling與cache/MMIO最佳化仍待驗證。
- PYNQ Linux沒有暴露`hwmon`、IIO或powercap rail sensor；相同routed checkpoint的Vivado
  vector-less power estimate為1.599 W total on-chip、0.147 W accelerator hierarchy，
  overall confidence為Medium且有reset activity準確度警告。由此乘上實測時間所得能量只能
  標為估算；在外接shunt/USB power meter或可校準rail monitor完成前，不可宣稱實測功耗。
