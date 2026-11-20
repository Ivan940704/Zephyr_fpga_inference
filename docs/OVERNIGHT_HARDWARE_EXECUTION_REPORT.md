# Zephyr FPGA 夜間硬體部署準備執行報告

日期：2026-09-07（Asia/Taipei）

執行分支：`codex/overnight-board-bringup`

狀態：**BLOCKED BEFORE PROGRAM**

> 歷史狀態註記：本報告記錄當時baseline `2293a02`的fail-closed結果。稍後的
> setup-pipelined baseline `eb496dd2`已解除timing blocker，產生matching BIT/HWH並於
> 同日完成具名PYNQ-Z1 JTAG programming及read-only ABI smoke；最新結論請以
> `PROJECT_STATUS.md`與`rtl/reports/accelerator_full_board/summary.md`為準。

## 結論

今晚已完成DMA-safe software reset架構、PS bring-up/recovery helper、warning
triage、fresh full Vivado implementation與first-board runbook。完整設計可在PYNQ-Z1
目標上完成route，standard 100 MHz setup與50 ps hold gate通過，但固定的
`+0.250 ns` setup engineering-margin gate仍短少53 ps。因此實作器依fail-closed
契約停在`write_bitstream`之前；沒有產生accelerator BIT/HWH、沒有program PL，也
沒有board measurement。

## 工作包執行結果

| 工作包 | 結果 | 證據／裁決 |
| --- | --- | --- |
| WP0 基線凍結 | PASS | 原始dirty checkout保持不動；在`codex/overnight-board-bringup`隔離worktree工作。計畫commit為`a1ecd36`。 |
| WP1 Setup margin | BLOCKED | 最佳純setup build為standard WNS `+0.199 ns`、guardbanded `-0.051 ns`；依計畫停止第三次純strategy/seed嘗試。Reset-safe baseline的正式route為`+0.197/-0.053 ns`。 |
| WP2 Reset/DMA safety | RTL/HOST PASS | Commit `2293a02`。Software reset只進custom data plane；DMA/mailbox/HP infrastructure維持存活。Persistent quiesce、兩拍safe proof、epoch與single-attempt host recovery均有測試。實板outstanding traffic仍未量測。 |
| WP3 Warning triage | PASS WITH NAMED RISKS | Post-route DRC為0 Error、0 Critical、115 Warning、18 Advisory；methodology為5 Warning。所有class有owner/處置，未waive或 suppress。 |
| WP4 BIT/HWH package | INTENTIONALLY NOT RUN | `full_gate_pass=0`；checkpoint manifest記錄`bit_files_found=0`、HWH command未呼叫。不得使用歷史parameter-BRAM artifact替代。 |
| WP5 PS bring-up | HOST PASS / BOARD BLOCKED | Helper核對ABI/address、mailbox frame、parameter alignment、三DMA Halted+Idle、barrier、reset epoch及read-only diagnostic snapshot。Repository尚無含PS LayerNorm round-trip的frozen end-to-end golden。 |
| WP6 交付 | PASS | 本報告、implementation summary、warning triage、reset/DMA契約及first-board runbook已建立；所有未量測項目保持NOT ACQUIRED。 |

## 最新完整實作 gate

Evidence baseline：`2293a0222d74175002ffb59bbea05d5dce98b45a`

工具／目標：Vivado 2018.3，`xc7z020clg400-1`，FCLK0 100 MHz

| Gate | 結果 |
| --- | ---: |
| Standard setup | WNS `+0.197 ns`、TNS 0、0 failing endpoints |
| 250 ps setup engineering guardband | WNS `-0.053 ns`，FAIL |
| 50 ps hold guardband | WHS `0.000 ns`、THS 0、0 failing endpoints，PASS at threshold |
| Raw physical hold | `+0.050 ns` |
| Route | 56,285/56,285 routable nets；0 routing errors |
| Timing coverage／CDC | 0 clockless/unconstrained internal/loops；all reported CDC paths safely timed |
| Resources | 30,007 LUT、34,964 FF、74 RAMB36、7 RAMB18、46 DSP；各類低於80% |
| DRC／methodology | 0 Error、0 Critical；115 DRC Warning、18 Advisory、5 methodology Warning |
| Required reports | 全部產生 |
| BIT/HWH／board | 未呼叫／未產生／未連板 |

最差standard setup path位於sparse-memory service，從`tentative_count0_q[8]`
經DSP/carry-chain的planned-byte計算到`diag_planned_bytes[13]`，data path為
9.546 ns、八層logic。第二條路徑的driver fanout為999，93.3%是routing delay；
placer congestion在同一sparse區域達level 5。下一步應註冊／分割診斷計算與
parameter-buffer write cone，而不是再用directive或seed碰運氣。

## Reset與DMA安全邊界

已完成的recovery順序為：停止新提交、ABORT、清除三個DMA channel的RS、確認每個
channel皆Halted+Idle且無error、assert persistent reset-quiesce、等待兩拍registered
safe、只送出一次soft reset、等待live control plane的epoch改變、重新核對ABI，最後
才acknowledge IRQ。Timeout或拒絕均保留診斷且不重試；quiesce fence無software cancel，
失敗後必須由operator明確選擇overlay reload或power-cycle。

這個契約避免software reset直接截斷AXI infrastructure，但不是實板證據。板上仍須
注入outstanding MM2S/S2MM/HP0 traffic、cache maintenance、timeout與reprogram/power-cycle
流程，才能把reset recovery升級為board PASS。

## 驗證紀錄

- Control XSim：PASS（2,245 ns），包含reset-quiesce／unsafe rejection／epoch。
- Top feature XSim：PASS；timing-cut 7 checks、DF coefficient store 64/1,152、
  mailbox adapter 782 bytes/5 reads、DeepFilter 2,573 checks/2,304 reads/256 outputs、
  feature dispatcher 101 checks/6 subband reads。
- Connected sparse XSim：PASS，12,446,068 checks。
- Fresh Vivado full implementation：完成；implementation Tcl本身return 0，wrapper因
  release metrics gate失敗而return non-zero，屬預期fail-closed結果。
- Host regression：169/169 PASS；其中implementation contract與PS helper的focused
  subset為16/16 PASS。
- Frozen/source checksum：`docs/memory/SHA256SUMS` 35/35、
  `docs/frozen/PE_MEMORY_V4_SHA256SUMS` 25/25、PE baseline 158/158、
  sparse import 47/47，合計265/265 OK。
- `git diff --check`通過；runner `.cmd`只有Git預告的LF-to-CRLF正規化提示。

## 尚未解除的部署阻擋

1. 將standard setup WNS從`+0.197 ns`提高至少53 ps，達到`+0.250 ns`；同時保留
   50 ps hold gate。現在的hold只是剛好在門檻，下一輪不可犧牲它換setup。
2. 建立repository-tracked、包含PS LayerNorm mailbox round-trip的完整輸入／輸出
   bit-exact golden，不能由leaf/PE/sparse PASS外推。
3. 在所有P0 gate通過後，從同一clean commit fresh build matching BIT/HWH及SHA-256
   manifest；目前沒有合格accelerator artifact。
4. 由operator提供並確認具名PYNQ-Z1 endpoint，再依runbook執行DDR、三DMA、mailbox、
   reset stress、multi-frame state、RTF、功耗與音訊量測。

## 早上接手入口

- 實作摘要：`rtl/reports/accelerator_full_bd_implementation/summary.md`
- Raw metrics：`rtl/reports/accelerator_full_bd_implementation/metrics_post_route.txt`
- Reset/DMA契約：`docs/HARDWARE_RESET_AND_DMA_RECOVERY.md`
- Warning triage：`docs/HARDWARE_IMPLEMENTATION_WARNING_TRIAGE.md`
- Board runbook：`docs/PYNQ_Z1_ACCELERATOR_BOARD_RUNBOOK.md`
- Host helper：`software/pynq/accelerator_bringup.py`

在setup與end-to-end golden兩個P0 blocker解除前，正確動作是繼續RTL/host工作，
不是program板子。
