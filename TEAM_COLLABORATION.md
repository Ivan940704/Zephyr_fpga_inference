# Zephyr FPGA 共編方式

本專案以 Git 歷史作為共編的正式紀錄。初始環境與專案結構已完成，後續一般工作
不建立 task card；開始前只需先確認 `PROJECT_STATUS.md`、
`docs/PYNQ_Z1_FEASIBILITY_CHECKLIST.md` 與目前 Git 狀態。

## 唯一固定要求

每次完成的更新都必須形成可追蹤的 Git commit，不能只留在某台電腦的 working
tree。提交時只 stage 本次工作範圍內的檔案，不得把其他人未完成或不相關的修改
一起提交。若已設定 shared remote，交接前再將 commit 或所在 branch push 上去。

## 簡化流程

1. 先讀 `PROJECT_STATUS.md`，確認目前階段、已驗證範圍與尚未完成項目。
2. 讀 `docs/PYNQ_Z1_FEASIBILITY_CHECKLIST.md`，確認本次變更適用的限制與證據等級。
3. 執行 `git status --short --branch`，確認目前 branch 與既有修改。
4. 完成修改、執行相稱的檢查，並用 `git diff` 確認範圍。
5. 只 stage 本次更新的檔案，以能說明成果的訊息建立 commit。
6. 有 shared remote 時，在需要分享或交接前 push。

一般工作不建立 task card，只有使用者明確要求時才建立。handoff、decision、
`PROJECT_STATUS.md` 更新、獨立 branch 與 pull request 都是按需使用，不必為每個
checkpoint 補齊。

## Repository 邊界

- 外層倉庫保存 FPGA 估算、報告、產物與選用的協作紀錄。
- `upstream/` 是獨立的 `allen_Zephyr` Git repository。若修改其中內容，必須先在
  `upstream/` 內建立 commit，再於外層 repository 提交更新後的 gitlink。
- 不得刪除 `upstream/.git`、把 nested repository 攤平，或提交他人的 dirty
  changes。

## 基本安全與證據

- 不要提交 API key、密碼、token 或不必要的私人路徑。
- 不覆蓋、丟棄或大量格式化其他人的未完成工作。
- 技術報告仍應區分分析估算、RTL/testbench、Vivado 與實板證據；沒有執行的驗證
  不得宣稱已完成。
