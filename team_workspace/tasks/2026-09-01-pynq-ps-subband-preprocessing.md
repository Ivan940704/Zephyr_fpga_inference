# Task: 記錄 PYNQ PS subband preprocessing 邊界

- Owner: Codex
- Status: complete
- Branch: `codex/pynq-ps-subband-preprocessing` requested; no branch can be
  created before the outer repository has an initial commit.
- Scope:
  - 記錄 subband frequency unfold、feature concatenation 與 subband LayerNorm
    在 PYNQ-Z1 的 PS CPU 執行，而不是 PC 或 PL RTL。
  - 更新共用進度、RTL boundary 說明與架構估算的適用範圍。
  - 定義後續 PS/PL 介面與驗證工作，但不先假定尚未決定的 transport 細節。
- Out of scope:
  - 實作 PS software、LayerNorm kernel、AXI/DMA driver 或新 RTL。
  - 決定 LayerNorm 使用 float32、NEON、fixed-point 或具體量化格式。
  - 修改已有未提交變更的 `upstream/` nested repository。
- Acceptance checks:
  - [x] 建立 accepted architecture decision。
  - [x] `PROJECT_STATUS.md` 與 `rtl/README.md` 清楚區分 PC、PYNQ PS 與 PL。
  - [x] `ZEPHYR_FPGA_ESTIMATE.md` 標出舊 LayerNorm PL 估算已被此決策取代。
  - [x] 記錄 PS/PL boundary 尚待固定的 tensor shape、dtype、layout 與 handshake。
  - [x] 建立 handoff 並將本任務標成 complete。
