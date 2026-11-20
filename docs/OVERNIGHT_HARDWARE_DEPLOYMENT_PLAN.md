# Zephyr FPGA 夜間硬體部署準備計畫

日期：2026-09-07（Asia/Taipei）  
執行分支：`codex/overnight-board-bringup`  
起始基線：`8c0d0b1`（50 ps full-design hold margin gate）

## 目標與今晚的完成定義

今晚的目標不是在缺少板卡身分、matching artifact 或安全 reset 契約時勉強燒錄，
而是把目前已 route 的 accelerator 推進成「可安全開始 PYNQ-Z1 board bring-up」的
候選交付物。工作依賴順序固定如下：

1. 改善或明確裁決 setup engineering margin。
2. 關閉 outstanding DMA/HP traffic 遇到 software reset 的安全缺口。
3. 分類 implementation DRC/methodology warnings，修正可安全處理的項目。
4. 僅在前述 gate 通過後，從乾淨 input 重建 matching BIT/HWH 與 manifest。
5. 提供 fail-closed 的 PS bring-up driver、mock tests 與板端操作順序。

今晚可宣稱完成的最高證據等級是：可重現的 RTL/XSim、full Vivado
implementation、可追溯 BIT/HWH artifact 與 host-side driver 測試。只有實際連接並
量測 PYNQ-Z1 後，才可宣稱 board PASS、RTF、功耗或音訊品質。

## 時程與工作包

時間是相對於本計畫開始執行的工程時間；Vivado route 可能使個別區段延長。

| 時段 | 工作包 | 動作 | 通過條件 | 失敗／停止條件 |
| --- | --- | --- | --- | --- |
| T+0:00–0:30 | WP0 基線凍結 | 核對狀態、限制、reports、source/hash 與 dirty tree | 使用隔離乾淨分支；原始 checkout 不被修改 | 發現 input 或報告不一致時先修復 provenance，不進下一關 |
| T+0:30–3:00 | WP1 Setup margin | 分析最差 setup path、高 fanout 與 congestion；只採用保持 cycle/ABI 的低風險 RTL/implementation 改善；跑 focused test 與 full route | 100 MHz WNS 至少 `+0.250 ns`；TNS 0；raw hold `>= +0.050 ns`；無新增 timing exception | 最多兩個完整 implementation 嘗試；若仍未達標，保留最佳不退步結果並把 artifact gate 標成 BLOCKED |
| T+3:00–5:00 | WP2 Reset safety | 建立 DMA quiesce、abort/drain、data-plane reset、reload 的明確順序；補 RTL/control/driver guard 與 fault-injection tests | reset 不會截斷已接受的 AXI transaction；timeout 可診斷且 fail closed；重啟要求 parameter reload | 無法由可觀測 idle 狀態證明安全時，禁止 driver 發 reset，BIT/HWH gate 維持 BLOCKED |
| T+5:00–5:45 | WP3 Warning triage | 對 DRC 113 warnings、methodology 5 warnings與 DDR DQS critical warnings逐類歸因 | 0 Error/Critical DRC；每個 warning class 有 owner、影響、處置或具名風險接受 | 不壓低或 waive 未理解的 warning；發現 blocking class 即停止 artifact 生成 |
| T+5:45–7:15 | WP4 Artifact | fresh allowlist build；route gate 後產生同版 BIT/HWH；保存 tool/part/clock/address/ABI/source/image/report hashes | BIT/HWH basename 配對；manifest hash 全部可驗；commit/source、100 MHz、part、address map 與 ABI 一致 | 任何 gate/hash/來源不符即刪除候選資格，不進板端 program |
| T+7:15–9:30 | WP5 PS bring-up | 完成 overlay identity、DMA buffer ownership/cache maintenance、mailbox ordering、IRQ/polling、timeout/reset/cleanup driver與 mocks | host mock 覆蓋 happy path、timeout、bad identity、frame mismatch、reset recovery；所有既有 tests PASS | driver 不能確認 HW ID/ABI 或 contiguous physical buffer 時 fail closed |
| T+9:30–10:00 | WP6 交付 | 更新 status/handoff，列出 board runbook 與未量測項目，提交所有完成更新 | working tree clean；每個完成工作包有 commit 與 matching evidence | 不把未跑測試寫成 PASS，不把 implementation 結果寫成 board evidence |

## 今晚固定的硬體 gate

- Target：`xc7z020clg400-1`，PYNQ-Z1 preset，FCLK0/PL/AXI 100 MHz。
- Setup：WNS `>= +0.250 ns`、TNS 0、setup failing endpoints 0。
- Hold：placement/route 使用 50 ps hold guardband；guardbanded WHS `>= 0`；移除
  人工 guardband 後 raw physical hold margin `>= +0.050 ns`。
- Route/coverage：0 routing errors、0 unrouted nets、0 clockless registers、0
  unconstrained internal endpoints、0 combinational/latch loops。
- CDC/DRC：CDC safely timed；DRC 與 methodology 0 Error、0 Critical Warning。
- Resource：LUT、FF、BRAM36-equivalent、DSP 各自低於 device capacity 80%。
- Functional：變更影響到的 focused XSim/Python tests 與完整 repository regression
  必須通過；不得用 false path 或 multicycle exception 隱藏真實同步路徑。

## Reset 與 DMA 的安全順序

PS software 的 recovery 順序固定為：

1. 禁止提交新 frame、mailbox command、parameter load 與 DMA descriptor。
2. 停止 accelerator 接收新 AXIS packet，等待或 abort 兩個 DMA channel。
3. 等待 DMA idle，以及 custom HP0 parameter master 完成 accepted AR/R 或 abort-drain。
4. 清除 DMA status/IRQ；確認 stream packet ownership 已回到 software。
5. assert data-plane reset；control plane 必須保持可讀。
6. deassert reset，核對 HW ID/ABI、清 sticky fault，重新配置 DMA。
7. flush parameter image、執行 memory barrier、重新載入 stage/cache，再允許 START。

若任一步驟 timeout，driver 保留 first-fault 診斷、停止新工作且不重複脈衝 reset。
使用者必須明確選擇重新 program overlay 或 power-cycle，不能由軟體猜測恢復成功。

## Artifact provenance

候選部署目錄必須包含：

- 同一個 fresh Vivado project 產生的 `.bit` 與 `.hwh`。
- SHA-256 manifest，涵蓋 BIT、HWH、v4 image、layout/golden、關鍵 timing/DRC/
  methodology/route reports 與產生腳本。
- Git commit、完整 source input commit/allowlist hash、Vivado version、FPGA part、
  board preset、clock、address map、HW ID、ABI version、parameter image version。
- 清楚標示 `implementation evidence` 與 `board evidence`；板測 log 不存在時一律
  記為 `NOT ACQUIRED`。

## 板端操作授權邊界

今晚可以安全執行本機測試、Vivado build、artifact 生成與只讀 JTAG 裝置枚舉。
只有在 endpoint 被明確識別為目標 PYNQ-Z1、artifact manifest 完整、所有 P0 gate
通過時，才可 program PL。沒有明確 endpoint、網路位址或登入方式時，不掃描網路、
不猜測 IP/帳密，也不把 2026-09-05 的歷史 JTAG 枚舉當成本次連線證據。

## 早上交付格式

交付摘要依序列出：實際完成項目、每個 gate 的數值、commit、artifact hashes、
測試結果、未完成原因、是否可安全 program、第一次 board smoke 的精確命令與回復
方式。若 setup/reset 任一 P0 gate 未通過，結論必須是 `BLOCKED BEFORE PROGRAM`。
