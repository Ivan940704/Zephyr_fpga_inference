# Task: 建立共用專案進度入口

- Owner: Codex
- Status: complete
- Branch: `codex/project-status-index` requested; no branch can be created
  before the outer repository has an initial commit.
- Scope:
  - 在專案根目錄建立一份供新成員閱讀的單一進度入口。
  - 彙整目前架構邊界、已完成 RTL、測試證據、限制、未完成工作與下一步。
  - 將原始設計簡報保存至共用專案並記錄檔案雜湊。
  - 把「每完成一個 checkpoint 必須更新進度入口」加入團隊規則。
  - 連結現有 task、handoff 與 decision 紀錄，保留詳細歷史而不重複改寫。
- Out of scope:
  - 修改 RTL、testbench 或 `upstream/`。
  - 宣稱尚未執行的 synthesis、implementation 或 PYNQ-Z1 板測結果。
  - 建立 Git commit 或發布 GitHub 倉庫；外層倉庫目前尚無初始 commit。
- Acceptance checks:
  - [x] 共用進度頁能讓新成員辨識完成、進行中、未開始與已驗證範圍。
  - [x] 簡報副本位於共用專案，SHA-256 與原附件一致。
  - [x] `AGENTS.md`、`TEAM_COLLABORATION.md` 與 workspace 索引要求 checkpoint 更新。
  - [x] 所有本地 Markdown 連結與所引用的測試證據均可讀取。
  - [x] 建立 handoff 並將本任務標成 complete。
