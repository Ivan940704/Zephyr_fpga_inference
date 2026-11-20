# Zephyr FPGA 推論延遲、RTF 與資源估算

> **2026-09-01 架構更新：**subband frequency unfold、concatenation、LayerNorm
> 與 INT8 packing 已改由 PYNQ-Z1 PS CPU 執行；fullband LayerNorm 暫時維持在
> 外部 PC/host。這項決策取代本文原先的 PL LayerNorm lane/cycle/DSP/LUT 假設。
> 下列仍含 LayerNorm 的 cycle 與 resource 數字是舊版分析資料，尚未重算；新的
> system RTF必須加入PS preprocessing，以及每frame 64-byte GP mailbox read與
> 782-byte GP mailbox write/commit的實測時間；這段繞過DDR controller。External
> fullband ingress/final egress仍需另計AXI DMA時間。
> 決策紀錄見
> [`team_workspace/decisions/2026-09-01-pynq-ps-subband-preprocessing.md`](team_workspace/decisions/2026-09-01-pynq-ps-subband-preprocessing.md)。

## 結論

本估算的 FPGA 邊界與原 repository 一致：輸入外部 STFT 的 real/imag bins 與 `|X|^0.5`，FPGA 執行 8 個 GSU、4 個 Linear 與 DeepFilter complex MAC，輸出 bins 0–255；**不含 STFT、ISTFT、音檔讀取與主機傳輸**。

分析所用的上游 snapshot 是 commit `13ea1405c9a400aac647025a42b216975765a9bb`（2026-08-23）。

建議的基準架構是假設：

- 100 MHz
- 64 個 INT8 MAC lanes，每 lane 每 cycle 做 1 次 INT8 multiply-accumulate
- 8 個 requantization lanes
- 舊版假設：1 個 PL LayerNorm lane，reciprocal-square-root 每個 vector 16
  cycles；已被 2026-09-01 PS preprocessing 決策取代
- 每個 frame 額外保留 256 cycles 給 routing、pipeline fill/drain 與控制
- 利用 `shared_weights=true`：每個 GSU 的兩個 gate 共用同一組 dot product，之後才分別 requantize
- 音訊範例暫用 16 kHz、`center=true`；repository 沒有固定 sample rate，也沒有固定 center/padding 行為

在這些假設下：

| 項目 | 建議 shared-weight 架構 | 直接照 manifest 的 2H 權重運算 |
| --- | ---: | ---: |
| INT8 MAC/multiply 每 frame | 2,138,432 | 3,996,032 |
| Requant multiply 每 frame | 33,920 | 33,920 |
| 估計 cycles/frame | 39,761 | 68,786 |
| 1 秒、16 kHz、center=true 的 STFT frames | 126 | 126 |
| 估計 cycles/1 秒音檔 | 5,009,886 | 8,667,036 |
| 100 MHz FPGA-boundary latency | 50.099 ms | 86.670 ms |
| Accelerator-only RTF | 0.0501 | 0.0867 |

`shared_weights` 的節省是 bit-exact 可行的：本分析逐一比對 manifest 中 8 個 GSU 的 `weight_ih_q`、`weight_hh_q`，16 個 tensor 的前後兩半均完全相同。兩個 gate 的 bias 與 requantization 仍然各自保留。

## 1. 每個音檔需要多少 cycles

### 1.1 每個 frame 的模型工作量

GSU 的直譯 MAC 數為：

```text
2H × (input_size + H)
```

但這個模型設定 `shared_weights=true`，硬體可改成：

```text
H × (input_size + H)
```

每一層與每個頻率 subband 的建議版 INT8 工作量如下：

| 區塊 | instances/frame | INT8 MAC 或 multiply/frame |
| --- | ---: | ---: |
| Fullband: GSU 64→320、GSU 320→320、Linear 320→64 | 1 | 348,160 |
| Subband 0: GSU 46→224、GSU 224→224、Linear 224→80 | 4 | 715,008 |
| Subband 1: GSU 94→224、GSU 224→224、Linear 224→192 | 3 | 643,776 |
| Subband 2: GSU 158→224、GSU 224→224、Linear 224→128 | 2 | 429,184 |
| DeepFilter: `4 × (32×5 + 96×3 + 128×1)` | 1 | 2,304 |
| **合計** |  | **2,138,432** |

另外有 33,920 次/channel 的 30-bit constant-multiplier requantization。本文舊版
估算器把 846 elements、10 vectors 的 LayerNorm 算在 PL；目前 64-element
fullband LayerNorm 留在 PC/host，另外 782 elements、9 vectors 的 subband
LayerNorm 移到 PYNQ PS，因此這段 LayerNorm cycles 不再是現行 PL 數據。

### 1.2 音檔長度換算

令 `T` 是外部 STFT 交給 FPGA 的 frame 數：

```text
cycles_audio = T × cycles_frame
```

如果外部 STFT 採用 PyTorch/librosa 常見的 `center=true`，對 `N` 個 samples：

```text
T = floor(N / 128) + 1
```

如果 `center=false`：

```text
T = 1 + floor((N - 512) / 128), N >= 512
```

因此「一個音檔」沒有單一固定 cycles；必須知道 sample rate、sample 數、center/padding，以及實際硬體平行度。可用計算器重算：

```powershell
python .\estimate_zephyr_fpga.py --duration-seconds 1 --sample-rate 16000 `
  --clock-mhz 100 --mac-lanes 64 --requant-lanes 8 --center
```

若硬體完全照 manifest 的 `2H` 權重做重複運算：

```powershell
python .\estimate_zephyr_fpga.py --duration-seconds 1 --sample-rate 16000 `
  --clock-mhz 100 --mac-lanes 64 --requant-lanes 8 --no-shared-weights
```

## 2. RTF

RTF 定義為：

```text
RTF = processing_time / audio_duration
    = cycles_audio / (f_clock × audio_duration)
```

基準設計對 1 秒、16 kHz 範例的 accelerator-only RTF 是 `0.0501`，意思是 FPGA 邊界內的運算約花音檔長度的 5.01%。長串流時可近似：

```text
RTF_FPGA ≈ 125 frames/s × 39,761 cycles/frame / 100,000,000
         ≈ 0.0497
```

完整系統必須另外量到：

```text
RTF_system = (t_STFT + t_transfer_in + t_FPGA + t_transfer_out + t_ISTFT + t_IO)
             / audio_duration
```

所以目前能 defensibly 報告的是 `RTF_FPGA ≈ 0.050`，不能把它寫成已實測的 whole-system RTF。

平行度敏感度（皆為 100 MHz、shared-weight；requant lanes 分別為 MAC lanes/8）：

| INT8 MAC lanes | Requant lanes | 估計 cycles/frame | 1 秒音檔 cycles | Accelerator-only RTF |
| ---: | ---: | ---: | ---: | ---: |
| 16 | 2 | 152,720 | 19,242,720 | 0.1924 |
| 64 | 8 | 39,761 | 5,009,886 | 0.0501 |
| 256 | 32 | 11,528 | 1,452,528 | 0.0145 |

## 3. 面積／FPGA 硬體資源

這個 GitHub repository 沒有 RTL/HLS、target FPGA、clock constraint 或 synthesis report，因此 LUT/FF/DSP 只能是架構估計；BRAM 則可以先從參數容量得到較可靠的下限。

### 3.1 記憶體

| 項目 | bytes | BRAM36 理論下限 |
| --- | ---: | ---: |
| 原始 `parameters.bin` | 2,193,288 | 476 |
| 其中匯出的 INT8 weights | 1,802,112 | 392 |
| 利用 shared-weight 後的 unique INT8 weights | 956,096 | 208 |
| 僅做 shared-weight 去重後的全部參數 | 1,347,272 | 293 |
| 9 組 sequence context 的 recurrent states | 9,344 | 3 |

BRAM36 下限使用 `ceil(bytes × 8 / 36,864)`。實際還會有 width/depth fragmentation、banking、double buffer、activation FIFO 與 line buffer。對 64-lane 設計，建議先抓：

- **全部參數 on-chip、shared-weight 與 metadata width 最佳化：250–310 BRAM36**
- **直接存原始 blob：至少 476 BRAM36，banking 後約 500–560 BRAM36**
- **權重放外部DDR：目前correctness baseline的256 KiB parameter cache結構估算約64 BRAM36，另有4 KiB LayerNorm mailbox約1 BRAM36，再加state/FIFO；16 kHz realtime的最低weight traffic約120 MB/s，若每個subband重讀權重則約267 MB/s。這些cache/mailbox數字尚未經Vivado inference。**

### 3.2 64-lane 建議設計的 pre-synthesis 範圍

| 資源 | 估計 | 假設／主要來源 |
| --- | ---: | --- |
| DSP slices | 64–100（舊範圍） | 64 個 INT8 MAC；8 個 32×30 requant lanes 若每個用 4 DSP。舊範圍含少量 LayerNorm DSP，現行 PS placement 應在重算時移除 |
| BRAM36 | 250–310 on-chip weights；或DDR + provisional 64-cache + 1-mailbox，再加state/FIFO | parameter cache/mailbox為結構估算；實際取決於v3 stage、width/depth mapping、banking與其他buffers |
| LUT | 15k–30k（舊範圍） | 控制、address generation、requant/round/saturate、BRAM/DDR interface；舊範圍的 PL LayerNorm LUT 應在重算時移除；低信心 |
| FF | 20k–45k | MAC pipeline/accumulator、控制與串流暫存；低信心 |

這些不是 Vivado 數字。選定 FPGA part、DDR/on-chip 策略、完成 PL RTL 與 PS
LayerNorm software 後，應用 `report_utilization`、`report_timing_summary`、
post-route simulation與板上parameter HP、GP mailbox、external DMA benchmark替換上述範圍。

## 尚未封閉的規格

在能把估算升級成實測前，還需要固定：

1. FPGA 型號／板子與目標 clock。
2. 音訊 sample rate、音檔長度，以及 STFT 的 `center/padding`。
3. PS LayerNorm 的 mean/variance/epsilon/affine/rounding 規格、輸出 INT8 scale，
   以及 float32、NEON 或 fixed-point 實作選擇。
4. 權重全放 BRAM/URAM，或從 DDR 串流；是否利用 shared-weight。
5. STFT/ISTFT 是否也要算進「系統 RTF」。

## PYNQ-Z1 專用估算

### 板子限制

PYNQ-Z1 使用 `XC7Z020-1CLG400C`，PL 端共有 53,200 LUT、106,400 FF、140 個 BRAM36、220 個 DSP48E1；板上另有 512 MiB、16-bit、1050 MT/s DDR3。

即使只做shared-weight去重，模型參數仍需要至少293個BRAM36，超過板上的140個；
原始`parameters.bin`更需要至少476個。因此PYNQ-Z1必須把主要權重放在PS DDR3，
PL只保留recurrent state、activation/FIFO、parameter stage/tile cache、獨立4 KiB
LayerNorm mailbox與external DMA所需frame buffers。

### 未做額外模型／資料流最佳化的基準

這裡把「未優化」定義成：直接執行 manifest 的 `2H` GSU 權重、不利用 shared-weight、不 pruning、不跳過 zero spike、不做 DSP packing，也不跨 subband 重用 weights。原本 FPGA inference bundle 已經是 INT8 QAT，所以並不是從 FP32 開始的完全未量化模型。

完全不做 weight caching 時，為了匹配單一 64-bit AXI HP port 在 100 MHz 時每 cycle 最多 8 bytes 的介面寬度，可採用：

- PL clock：100 MHz
- 8 個 INT8 MAC lanes
- 1 個 requantization lane
- 權重由 DDR3 經 64-bit AXI HP port 串流
- 舊版仍採前述PL LayerNorm latency；現行PS placement需重算並加入GP mailbox
  MMIO/commit與CPU preprocessing實測時間，external ingress/egress才另計DMA

這個「每個 MAC 都直接向 DDR 取 weight」的最差模型結果如下：

| 項目 | PYNQ-Z1 未額外優化基準 |
| --- | ---: |
| INT8 MAC/multiply 每 frame | 3,996,032 |
| 估計 cycles/frame | 535,532 |
| 1 秒、16 kHz、center=true frames | 126 |
| 純計算 cycles/1 秒音檔 | 67,477,032 |
| 純計算時間 @ 100 MHz | 674.770 ms |
| Compute-only RTF | 0.6748 |
| 最差情況權重讀取量/1 秒音檔 | 503,209,728 bytes |

單一 64-bit AXI HP port 在 100 MHz 的介面理論值是 800 MB/s，所以讀完上述權重至少約 629 ms；使用規劃用、尚未實測的 600 MB/s sustained bandwidth，則約 839 ms。若權重串流和 MAC 理想重疊：

```text
RTF lower bound = max(compute time, DDR time) / audio duration
```

上述 503 MB 並不是模型檔大小，而是同一組 weights 在每個 frame、每個 subband 都重新讀取造成的放大流量。它只適合當作「無 cache、無 reuse」的最差情況，不應作為建議架構。

### 建議的 weight-stationary 實作

PYNQ-Z1 的 140 個 BRAM36 雖然放不下全部 2.19 MB 參數，但可以一次暫存一個 layer 的 weight tile。最大的單一 exported operator 約 470 KB、其中 weights 約 410 KB；逐層載入後，讓該層跑完整個音檔的所有 frames，再換下一層。如此每個音檔只需從 DDR 載入完整參數一次：

```text
DDR traffic/audio = 2,193,288 bytes
DDR time @ 600 MB/s = 3.655 ms
DDR time @ 800 MB/s = 2.742 ms
```

使用原先可放入 XC7Z020 的 64 MAC lanes、8 requant lanes，且仍不利用 shared-weight 時：

```text
compute cycles/audio = 8,667,036 cycles
compute time @ 100 MHz = 86.670 ms
compute-only RTF = 0.0867
```

如果 weight loading 與計算不重疊，保守相加：

```text
total @ 600 MB/s = 86.670 + 3.655 = 90.325 ms
RTF ≈ 0.0903
```

若用 double buffer 把下一層載入與目前層計算重疊，結果會接近 `RTF 0.0867`。因此目前建議對 PYNQ-Z1 報告：

```text
純計算：8,667,036 cycles，RTF 0.0867
含逐層 DDR loading：RTF 約 0.087–0.091
極端無 cache、每次 MAC 讀 DDR：RTF 約 0.7–0.9
```

可重算命令：

```powershell
python .\estimate_zephyr_fpga.py --duration-seconds 1 --sample-rate 16000 `
  --clock-mhz 100 --mac-lanes 64 --requant-lanes 8 --no-shared-weights `
  --weight-bandwidth-mbps 600 --weight-load-scope audio
```

### PYNQ-Z1 pre-synthesis 資源估計

| 資源 | 估計使用 | XC7Z020 可用 | 約占比 |
| --- | ---: | ---: | ---: |
| DSP48E1 | 64–100 | 220 | 29–45% |
| BRAM36 | 105–135 | 140 | 75–96% |
| LUT | 15k–30k | 53,200 | 28–56% |
| FF | 20k–45k | 106,400 | 19–42% |

這個範圍假設使用minimal custom overlay；若同時保留大型PYNQ base overlay，剩餘
資源會更少。Parameter HP path、GP/AXI BRAM Controller mailbox、external DMA與AXI
interconnect的資源、MMIO latency及sustained bandwidth必須以Vivado implementation和
板上microbenchmark更新。

### Fullband 後三個 Subband 並行

建議排程為：

```text
Fullband
   ├─完成後啟動─ SB0（4 個 local subbands）
   ├─完成後啟動─ SB1（3 個 local subbands）
   └─完成後啟動─ SB2（2 個 local subbands）
```

三個 branch 的 latency 取最大值，不再相加。對 PYNQ-Z1 可行的起始配置是每個
branch 48 個 INT8 MAC lanes、4 個 requant lanes；Fullband 階段先借用其中一套
引擎。此設計總共需要 144 個 MAC DSP，剩餘 DSP 給 12 個 requant lanes；
LayerNorm 已移至 PS/host，不再配置 PL DSP。下表 cycles 仍含舊 LayerNorm
假設，必須重算後才可作為現行 partition 的 PL latency。

若利用模型原生的 `shared_weights=true`：

| 階段 | cycles/frame |
| --- | ---: |
| Fullband | 8,792 |
| SB0 | 18,826 |
| SB1 | 16,807 |
| SB2 | 11,511 |
| 並行 Subband latency `max(SB0,SB1,SB2)` | 18,826 |
| **總計** | **27,618** |

對 1 秒、16 kHz、126 frames：

```text
cycles/audio = 27,618 × 126 = 3,479,868 cycles
compute time @ 100 MHz = 34.799 ms
compute-only RTF = 0.0348
```

shared-weight 後的參數約 1,347,272 bytes；以 600 MB/s 載入約 2.245 ms。若不與計算重疊，估計 `RTF ≈ 0.0370`；若 double buffer 重疊，接近 `0.0348`。

初步資源範圍：

| 資源 | 三路 48-lane 並行估計 | PYNQ-Z1 可用 |
| --- | ---: | ---: |
| DSP48E1 | 約 195–210 | 220 |
| BRAM36 | 約 110–130 | 140 |
| LUT | 約 30k–45k | 53,200 |
| FF | 約 35k–70k | 106,400 |

這個配置可行但很緊，應使用 minimal custom overlay。若不利用 shared-weight，三個最大 recurrent weight sets 同時常駐約需 600 KB，加入 banking、state、FIFO 和 DMA 後會超過可用 BRAM；此時只能降低 lanes、分tile由DDR反覆供應，或放棄完全同時的三路執行。

重算命令：

```powershell
python .\estimate_zephyr_fpga.py --duration-seconds 1 --sample-rate 16000 `
  --clock-mhz 100 --mac-lanes 48 --requant-lanes 4 --shared-weights `
  --parallel-subbands --weight-bandwidth-mbps 600 --weight-load-scope audio
```

### Sparsity-aware spike zero-skipping

Binary spike先由encoder產生非零index，再只讀取對應weight columns並累加。這個模型可套用的位置是：所有GSU recurrent `hx`、每個stack的第二層GSU input，以及4個Linear projection input；第一層GSU的一般INT8 feature與DeepFilter不能用spike zero-skip。

shared-weight版本每frame共2,138,432次INT8運算，其中1,940,480次（90.7%）位於sparsity-eligible路徑。令零spike比例為 `S`：

```text
effective INT8 ops/frame ≈ 197,952 + (1-S) × 1,940,480
```

對三路48-lane並行架構，並假設encoder每cycle掃描32個spike bits：

| Spike sparsity | Effective INT8 ops/frame | Cycles/frame | 1秒音檔compute RTF | 加一次參數載入、不重疊的RTF |
| ---: | ---: | ---: | ---: | ---: |
| 50% | 1,168,192 | 18,189 | 0.0229 | 0.0252 |
| 70% | 780,096 | 13,725 | 0.0173 | 0.0195 |
| 80% | 586,048 | 11,425 | 0.0144 | 0.0166 |
| 90% | 392,000 | 9,193 | 0.0116 | 0.0138 |
| 95% | 294,976 | 8,077 | 0.0102 | 0.0124 |

這些是假設所有eligible layers具有相同sparsity的情境分析。repository沒有提供真實音訊或各層spike-rate統計，所以正式結果必須用代表性測試集逐層量測；尤其SB0通常仍是critical branch，不能只使用全模型平均sparsity。

90% sparsity重算命令：

```powershell
python .\estimate_zephyr_fpga.py --duration-seconds 1 --sample-rate 16000 `
  --clock-mhz 100 --mac-lanes 48 --requant-lanes 4 --shared-weights `
  --parallel-subbands --spike-sparsity 0.90 --spike-encoder-width 32 `
  --weight-bandwidth-mbps 600 --weight-load-scope audio
```
