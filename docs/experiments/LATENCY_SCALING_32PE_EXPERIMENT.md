# Latency scaling feasibility experiment

日期：2026-09-08 至 2026-09-09（Asia/Taipei）

## 結論

這一輪適合繼續，但四項修改不能一次直接進 production：

1. 電腦端 STFT 與 spectrum magnitude 已實作、單元測試通過，並完成固定五檔同輸入
   PYNQ A/B。功能 5/5 PASS，但目前從板端儲存體載入完整 float NPY bundles 的方式沒有
   觀察到 latency 收益；單次量測的 frame latency 比 PYNQ-side control 慢 0.773%，
   end-to-end RTF 慢 1.257%。這不足以證明統計退化，但足以判定目前傳輸／載入方案沒有
   改善證據，暫不進 production latency path。
2. 32-lane Hybrid MAC bank 的 XSim 與 125 MHz OOC place-and-route 已完成；它證明
   32 個算術 lane 放得下且內部時序可行，不代表固定 16-PE 的 controller、memory、
   serializer 與完整 accelerator 已改成 32 PE。
3. 不建議現在把 AXI4-Stream 從 64 bit 改成 128 bit。Zynq-7020 PS7 HP port 仍是
   64 bit，現有每 frame 的 2,624-byte stream payload 最多只少 164 個 handshake cycle，
   在 125 MHz 是 1.312 us 上限，且不會讓 DDR bus 變成 128 bit。
4. 32-lane bank 的 125 MHz setup 與內部 hold 通過，但現有完整 ec457b1 full design
   在 100 MHz、250 ps guardband 下只剩 +0.014 ns WNS。若 netlist 不變直接改 125 MHz，
   setup slack 估計為 -1.736 ns，因此不能直接提高完整系統 clock 或產生新 bitstream。

## 證據分層

| 項目 | 結果 | 證據等級 |
|---|---:|---|
| Feature bundle unit tests | 2/2 PASS | host software rerun |
| 五檔 host feature generation | 5/5 PASS，平均 0.0681 s/檔 | Windows x86 measurement |
| 五檔同輸入 frontend A/B | 兩種模式均 5/5 PASS，共 46,274 frame-runs | PYNQ-Z1 measurement |
| PC 預算 frame latency 差異 | +0.773%（較慢） | 同輸入 PYNQ-Z1 A/B |
| 32-lane dense/direct checks | 64/64 PASS | Vivado 2018.3 XSim |
| 32-lane OOC setup @125 MHz | WNS +0.424 ns | OOC post-route |
| 32-lane internal reg-to-reg hold | +0.047 ns | OOC post-route |
| 32-lane OOC boundary hold | -1.226 ns | OOC boundary limitation，未隱藏 |
| 32-lane resources | 2,622 LUT、2,145 FF、32 DSP、0 BRAM | OOC post-route |
| Routing | 0 routing-error nets | OOC post-route |
| 完整 32-PE accelerator | 尚未實作 | UNKNOWN |
| 完整系統 125 MHz | 尚未收斂 | NOT TIMING CLOSED |
| 128-bit DDR bandwidth | HP port 固定 64 bit，不會加倍 | device/interface fact + estimate |

OOC wrapper 有 1,829 個 input bits 與 1,056 個 output bits；將輸入輸出 delay 設為
0.250 ns 且指定 `HD.CLK_SRC` 後，所有 I/O 都有 timing constraint。負的 all-path hold
來自 OOC 邊界沒有實際上游同時鐘暫存器；報告另列內部 register-to-register hold，且不把
OOC 結果當成 full-system sign-off。

## 固定五檔基線

使用 file IDs `000, 025, 050, 075, 099`。下表是既有 ec457b1 PYNQ-Z1 實測，總計
23,137 frames、185.056 s evaluated audio。

| file ID | frames | mean frame (ms) | frame RTF | board-loop RTF | end-to-end RTF | SNR delta (dB) |
|---:|---:|---:|---:|---:|---:|---:|
| 000 | 4,874 | 11.274 | 1.410 | 2.689 | 2.801 | +4.642 |
| 025 | 4,708 | 10.920 | 1.365 | 2.674 | 2.785 | +18.427 |
| 050 | 4,417 | 11.165 | 1.396 | 2.722 | 2.839 | +4.694 |
| 075 | 4,623 | 11.250 | 1.406 | 2.722 | 2.831 | +0.188 |
| 099 | 4,515 | 10.734 | 1.342 | 2.652 | 2.769 | +8.595 |
| aggregate | 23,137 | 11.071 weighted | 1.384 | 2.692 | 2.805 | +7.338 audio-weighted |

五檔 host bundle 是從結果資料夾內的 `noisy.wav` 產生；這些檔案是原 runner 寫回的
PCM16 副本，和最初 dataset WAV 的 SHA 不同。因此後續板端 run 也固定使用同一批副本，
不把它和上表的原始 dataset run 宣稱為 bit-identical A/B。Feature 計算本身已由單元測試
證明和 runtime 的原公式逐值完全相等。

## 同輸入五檔板端 frontend A/B

為避免上述原始 dataset／回存 PCM16 差異，另以完全相同 input SHA 的五個回存 WAV 分別
執行 `computer_precomputed` 與 `pynq_cpu`。兩輪均使用 ec457b1、16 PE、100 MHz、
64-bit stream、bulk/native/sleep/optimized-cache/no-diagnostics；每檔前做 fresh epoch reset。
兩輪共 10 次 reset 均 epoch `+1`，30 個 DMA channel 先停止且 0 error，10 份 final
fault/control/DMA gate 全部 PASS。分析完成後另做 cleanup reset，epoch `5→6`，三個 DMA
均停止且 0 error，image identity 仍為 `0x00040002`；cleanup 後未再送 inference frame。

| file ID | PYNQ frontend frame ms | PC 預算 frame ms | 差異 | enhanced SHA 相同 |
|---:|---:|---:|---:|---:|
| 000 | 11.280 | 11.383 | +0.910% | 否 |
| 025 | 10.888 | 10.965 | +0.707% | 是 |
| 050 | 11.160 | 11.242 | +0.730% | 是 |
| 075 | 11.230 | 11.329 | +0.886% | 否 |
| 099 | 10.738 | 10.804 | +0.609% | 否 |
| aggregate | 11.062 weighted | 11.147 weighted | +0.773% | 2/5 |

Aggregate board-loop RTF 為 2.694→2.724（+1.138%），end-to-end RTF 為
2.807→2.842（+1.257%）。五檔 bundle load 共 7.411 s，PYNQ STFT compute 共
6.943 s；光載入就多 0.468 s（+6.739%），而移除每 frame magnitude 並未抵消 I/O 與
run-to-run 波動。因此不能把 PC 預算方案宣稱為 latency 改善；它目前只是運算位置移轉。

計時邊界需分開解讀：`mean_frame_ms` 從 `PynqAcceleratorRuntime.run_frame()` 內開始，
control 的每 frame magnitude 計算發生在呼叫之前，因此 +0.773% 不是 magnitude 本身的
直接量測。Board-loop 包含每 frame magnitude 選取／計算，但不含初始 STFT／bundle load；
end-to-end 才包含初始 frontend、frame loop 與輸出重建。每個模式目前只有一次五檔 run，
所以約 1% 的負差異可能包含系統波動；可下的結論是「沒有觀察到加速」，不是「已證明固定
退化 1%」。

x86 與 ARM NumPy FFT 的浮點尾數不是 bit-exact：最大 spectrum／magnitude 差分別為
`2.91e-11`／`4.77e-7`。通過目前 int8 介面後，11,846,144 個 spectrum 元素全相同；
1,480,768 個 fullband input 元素只有 1 個差 1 LSB。Enhanced WAV 為 2/5 SHA 相同；
其餘三檔合計 789,380／2,960,896 samples 不同，最大個別差 1,594 PCM LSB，但
audio-weighted SNR improvement 只由 +7.4430 變成 +7.4645 dB（+0.0215 dB）。這代表
跨平台 float 尾數可跨過後續 subband quantization 邊界；若要求 bit-exact output，應在
電腦端直接產生固定點／量化後傳輸格式，而不是交換 complex64/float32。

板端 raw evidence 保留在 `/home/xilinx/zephyr_latency_32pe_20260908/results/`；兩份 manifest
與 A/B comparison SHA-256 分別是 `0b94e0c2…159a`、`5c55bac8…b19f`、
`f856611c…aff9`。Repo 內摘要為
`rtl/reports/latency_scaling_experiment/board_frontend_ab_summary.json`。

## 電腦端 frontend

`software/host/precompute_audio_features.py` 在電腦端計算 centered STFT 與
`sqrt(abs(spectrum[:256]))`，輸出：

- `spectrum.npy`：`complex64 [257, frames]`
- `magnitude.npy`：`float32 [256, frames]`
- `metadata.json`：來源 WAV、陣列 SHA-256、shape、dtype、FFT/hop 與語義

`software/pynq/run_accelerator_inference.py --precomputed-features DIR` 會驗證所有 SHA、
shape、dtype、sample count 與來源 WAV，再直接使用 bundle。舊的 PYNQ CPU 計算路徑仍保留。

五檔 Windows x86 feature 計算時間為 0.0935、0.0625、0.0613、0.0620、0.0611 s，
平均 0.0681 s。這是電腦端時間，不是板端 latency，也未計入網路傳輸。

## 32 PE 與 clock 分析

代表性 fileid_081 hardware profile 排除第一 frame 後共有 4,245 frames：

- mean PL latency：10.484 ms @100 MHz
- mean stage compute：687,448 cycles，占 frame 65.57%
- mean `wait_ps`：184,579 cycles；提高 PL clock 不會讓 ARM service wall time等比例變快

把 16→32 lanes 視為可平行部分減半，並保留 `wait_ps` wall time，可得到下列估計：

| 情境 | 估計 PL latency | 相對目前 PL speedup |
|---|---:|---:|
| 只升 125 MHz | 8.757 ms | 1.197x |
| 32 PE @100 MHz，70% compute 可平行 | 8.078 ms | 1.298x |
| 32 PE @125 MHz，70% compute 可平行 | 6.832 ms | 1.535x |
| 32 PE @125 MHz，100% compute 可平行 | 6.007 ms | 1.745x |

這些是 bounded analytical projections，不是新 bitstream 或板測。完整 32 PE 需要把目前
128-bit/16-row tile 改成 256-bit/32-row tile，連帶修改 job controller 的 tile counts、
`tile*16+lane` indexing、memory image packing、membrane/postprocess、requant 與 serializer。
Frozen `rtl/pe_array/baseline/v1` 保持不變。

## Interface width 判斷

目前每 frame 的 accelerator-side stream payload：fullband 64 B、spectrum 512 B、output
2,048 B。64-bit 時是 328 beats，128-bit 時是 164 beats。即使每少一 beat 就真的省一個
clock，125 MHz 的上限也只有 1.312 us，相對 10.484 ms PL latency 小於 0.013%。此外 PS7
HP0-HP3 是 64-bit；把 DMA stream 端設成 128-bit 只會增加 width conversion，不會把 DDR
頻寬加倍。本輪不修改 production interface。

較值得優先做的是：parameter request prefetch、較長 burst、增加 outstanding reads、減少
`r_wait`，以及把 PS mailbox polling 改成 IRQ 或更粗粒度批次。

## 後續修改行程

1. 將 PC frontend bundle 改為已量化、可串流的緊湊格式，避免 complex64/float32 NPY
   載入與跨平台 FFT 尾數；先以 host/board quantized-input bit-exact test 做 go/no-go，
   不把目前方案併入 production latency path。
2. 依 32-row tile 新增 production-v2 controller/memory contract；先跑 Python oracle 與
   connected XSim，不修改 frozen v1。
3. 以 32 PE 完整 top 做 100 MHz synthesis/implementation，確認資源、routing、setup/hold；
   通過後才做 105/110/125 MHz sweep，先 pipeline critical path 再升頻。
4. 只有在 profile 證明 stream handshake 成為顯著瓶頸時，才加入 128-bit AXIS data-width
   converter 實驗；DDR HP port 仍維持 64 bit。
5. 完整 full BD 非負 WNS/WHS、clean timing coverage/routing、matching BIT/HWH 後，才可 JTAG
   program，再用同五檔做實板 A/B。未達 gate 前不覆寫目前可工作的 ec457b1 image。

## 可重現命令與輸出

- Host unit test：`python -m unittest software.tests.test_audio_feature_bundle -v`
- Host feature CLI：`python software/host/precompute_audio_features.py ...`
- Vivado：`rtl/scripts/Run-Latency-Scaling-32PE-Vivado.cmd`
- 分析：`python3 software/analysis/analyze_latency_scaling.py ...`
- 同輸入 A/B：`python3 software/analysis/compare_frontend_board_runs.py ...`
- Machine-readable 結果：`rtl/reports/latency_scaling_experiment/analysis.json`
- Board A/B 摘要：`rtl/reports/latency_scaling_experiment/board_frontend_ab_summary.json`
- OOC reports：`rtl/reports/latency_scaling_32pe_125mhz/`
