# Memory-only 遠端上傳清單

新的遠端專案已包含 `allen_Zephyr` repository 原始內容。本包是差異交接包；請將 `rtl_upload_bundle/` 的內容合併到新 repository 根目錄，或直接上傳 `rtl_upload_bundle.zip`。

## A. 可綜合 RTL 與生成的位址介面

| 路徑 | 用途 |
| --- | --- |
| `rtl/memory.v` | AXI4 read DMA＋dual-port BRAM cache |
| `rtl/model_memory_map.vh` | 生成的 stage 與 tensor local-offset 巨集，供後續 FSM／PE 使用 |

`model_memory_map.vh` 不是 `memory.v` 的直接 dependency，但它是新專案載入 memory stage 時需要的生成介面。

## B. Memory RTL 驗證

| 路徑 | 用途 |
| --- | --- |
| `sim/tb_memory.v` | self-checking AXI/BRAM testbench |
| `sim/run_memory_xsim.ps1` | Vivado Simulator compile／elaborate／run |
| `docs/MEMORY_RTL_GUIDE.md` | Memory 介面、狀態機、載入流程與限制 |

## C. Memory image 工具與測試

| 路徑 | 用途 |
| --- | --- |
| `tools/generate_axi_memory_image.py` | 從新專案既有 manifest／parameters 生成 AXI image、JSON map 與 Verilog header，並將兩個 gate 共用的 GSU weights／weight scales 只存一份 |
| `tests/test_axi_memory_image.py` | 驗證 stage alignment、shared-gate halves、packing metadata、非共用 tensor bytes 與最大 stage size |

## D. 已生成的 Memory runtime artifacts

| 路徑 | 用途 | SHA-256 |
| --- | --- | --- |
| `build/parameters_axi.bin` | 載入 DRAM `PARAM_BASE` 的 compact 64-bit AXI image（1,313,104 bytes） | `74afdb9a57c7e8863556c48e0e7a8ad3bb9661b27ccb8a2c4665b99c5e60e938` |
| `build/memory_layout.json` | Format v2 stage／tensor local offset、shared-gate packing 與 transfer map | `b4a5246fbaeacdedd73088237a9ce7660254b7e6d764253ed5a8b2132514def0` |

這兩個檔案可由 generator 重建，但首次交接保留已驗證版本，方便確認新專案使用相同的 image／header 組合。

目前最大 stage transfer 為 260,120 bytes。Header 中 `*_GATE_SHARED=1` 的 tensor 只存一份，PE 必須讓兩個 gate 重用相同位址；gate-specific bias 與 requantizer 不能共用。

## E. 刻意不包含的既有檔案

以下內容已由新專案的 `allen_Zephyr` 基底提供，不在本交接包中重複上傳：

```text
parameters/manifest.json
parameters/parameters.bin
model_spec/
audiozen/
source_weights/
calibration/
docs/ARCHITECTURE.md
docs/PARAMETER_MAP.md
README.md（原 repository 版本）
LICENSE
```

## F. 遠端快速檢查

在新 repository 根目錄執行：

```powershell
python tools/generate_axi_memory_image.py
powershell -ExecutionPolicy Bypass -File sim/run_memory_xsim.ps1
```

預期模擬最後出現：

```text
PASS: all memory controller tests passed
```

若重新執行 generator，請把 `build/parameters_axi.bin`、`build/memory_layout.json` 與 `rtl/model_memory_map.vh` 視為同一版本集合。
