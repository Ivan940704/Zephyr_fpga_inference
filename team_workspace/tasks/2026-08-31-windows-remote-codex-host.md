# Task: 將目前 Windows 筆電設定為 Codex 遠端開發主機

- Owner: User
- Status: in progress
- Branch: 尚未建立；本任務主要修改 Windows 主機設定
- Scope:
  - 盤點 Windows、Codex CLI、OpenSSH Server 與 Tailscale 狀態。
  - 安裝並啟動 Windows OpenSSH Server。
  - 將 SSH 存取限制在 Tailscale 私有網路，不直接暴露到公網。
  - 驗證 SSH 服務、Codex PATH、主機位址與遠端專案需求。
- Files expected to change:
  - `team_workspace/tasks/2026-08-31-windows-remote-codex-host.md`
  - `team_workspace/handoffs/2026-08-31-windows-remote-codex-host.md`
  - Windows OpenSSH、服務與防火牆系統設定
- Out of scope:
  - 未取得同學的 Windows 帳號名稱與 SSH public key 前，不建立同學帳號。
  - 不設定路由器 port forwarding，也不將 SSH 或 Codex app-server 暴露到公網。
  - 不共用使用者的 ChatGPT/Codex 登入憑證。
- Acceptance checks:
  - [ ] `sshd` 已安裝、正在執行並設定為自動啟動。
  - [ ] TCP 22 只允許來自 Tailscale 私有位址範圍。
  - [ ] 遠端登入 shell 可找到 `codex`。
  - [ ] 已記錄同學端設定步驟與尚待提供的 SSH public key。
- Notes:
  - 插電時睡眠目前為 Never；使用電池時仍會在 15 分鐘後睡眠。
  - 外層 Git repository 尚未有初始 commit 或 remote。
  - Codex 沙箱無法取得互動式 Windows UAC token；已建立
    `team_workspace/host_setup/Run-Setup-CodexRemoteHost.cmd`，等待使用者在桌面端
    執行一次後繼續驗證。
