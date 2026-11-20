# Task: 建立版本歷史與 PYNQ-Z1 feasibility gate

- Owner: Codex
- Status: complete
- Branch: `codex/version-history-pynq-gate`
- Scope:
  - 為目前沒有 commit 的 outer repository 建立可閱讀的初始 Git 歷史。
  - 將既有 `upstream/` 以 submodule metadata 與目前 HEAD pointer 納入外層，
    不提交或修改其既有 dirty worktree changes。
  - 加入 `.gitignore`，排除 Vivado/XSim/Python 的可重建暫存物。
  - 將 PYNQ-Z1 feasibility review 設為每個新 RTL/PS 模塊的必要設計與驗收 gate。
  - 更新共用進度、decision 與 handoff。
- Out of scope:
  - 為 outer repository 建立或推送 remote。
  - 提交、清理或重寫 `upstream/` 的既有未提交修改。
  - 重新執行全部 RTL/Vivado 測試；本任務驗證版本邊界與協作規則。
- Acceptance checks:
  - [x] 外層 repository 有初始 commits，commit messages 可辨識各 checkpoint。
  - [x] 工作 branch 為 `codex/version-history-pynq-gate`。
  - [x] `upstream` 以 gitlink 記錄目前 HEAD，dirty changes 保持原樣。
  - [x] Generated build/cache 不進入 Git，專案證據 logs/reports 保留。
  - [x] 每個模塊 task 必須記錄 PYNQ-Z1 resource、timing、memory/bandwidth 與
    PS/PL transfer feasibility；無證據時不得宣稱可上板。
  - [x] `PROJECT_STATUS.md`、decision 與 handoff 更新完成。
- PYNQ-Z1 feasibility: N/A；本任務只修改 Git 與團隊 governance，不新增
  hardware 或 PS datapath。Checklist 本身是此任務的交付物。
