# Memory RTL difference bundle

這是 Memory-only 差異交接包，應合併到已匯入 `allen_Zephyr` 內容的新 repository 根目錄。

本包包含：

- AXI4 read DMA＋BRAM cache RTL。
- 生成的 memory-map header 與 shared-gate compact AXI runtime image。
- Image repacker、testbench、模擬腳本與 Memory 文件。

本包刻意不重複提供模型程式、模型架構文件、model config、原始 manifest、`parameters.bin`、checkpoint 或 LICENSE。

Compact image 對兩個 gate 共用的 GSU input/recurrent weights 與 weight scales 只存一份；最大 stage transfer 已由 470,040 bytes 降至 260,120 bytes。Gate-specific bias 與 requantizer 仍完整保留。

目前 `memory.v` 只有 DRAM→BRAM read DMA。BRAM→DRAM writeback，以及 CPU LayerNorm 的 store／通知／CPU 計算／reload round-trip 尚未實作，詳見 `DESIGN_PROGRESS.md`。

Image generator 會使用新專案既有的：

```text
parameters/manifest.json
parameters/parameters.bin
```

重新產生 memory artifacts：

```powershell
python tools/generate_axi_memory_image.py
```

驗證 Memory RTL：

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_memory_xsim.ps1
```

完整 Memory 設計狀態請見 `DESIGN_PROGRESS.md`。
