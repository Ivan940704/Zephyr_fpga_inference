# Accelerator top Step 4 設計與驗證紀錄

日期：2026-09-05（Asia/Taipei）

## 結論

Step 4 已建立可綜合的 `accelerator_top`，把現行 global `fsm.v`、凍結的
Sequential v4 PE＋memory subsystem、`layernorm_mailbox` 與新的原子 frame
adapter 接在同一個 100 MHz clock domain。PE array 與 memory freeze 內的 RTL
位元內容沒有改動。

這是目前手寫的 PL RTL top，不是最後的 PYNQ-Z1 Vivado Block Design top。
正式上板時仍需要由 Vivado 產生的 PS7／AXI／reset wrapper 包在外層。

## Step 4 階層與責任

```text
future PS7 / AXI block-design wrapper
                 |
          accelerator_top
          |      |       |
        fsm   mailbox   frame adapter
          |                 |
          +--- sequential_v4_pe_memory_subsystem
                         |
                 frozen pe_array_datapath
```

- FSM 只用 stage request、job lifecycle、PE barrier 與 fault contract 控制
  subsystem；`parallel_subbands` 固定為 0。
- Fullband projection 的 stage 2 coefficient stream 必須依序產生 64 bytes。
  Adapter 在 job 被接受時配置 mailbox slot，完整發布後才回覆 FSM 的
  `fb_result_ready`。
- PS commit subband slot 不等於資料已可運算。Adapter 會依序檢查並緩衝完整
  782 bytes，等 mailbox release event 也確認後，才對 FSM 宣告
  `ps_subbands_valid`。
- 782-byte buffer 提供帶 frame ID、index 與 response backpressure 的同步讀取
  介面，留給下一步 dense-feature dispatcher 使用。
- Mailbox、adapter 或 unsupported coefficient protocol fault 都會進入 FSM 的
  reset-required error contract；`clear_error` 不會繞過這個規則。

## 驗證結果

| 檢查 | 結果 | 可支持的結論 |
|---|---|---|
| `Run-Accelerator-Top-Step4-XSim.cmd` | PASS | 64-byte FB publish、PS BRAM 196-word write、782-byte atomic buffer、release、random read backpressure、frame advance與錯誤注入通過；`accelerator_top`可完整elaborate |
| Vivado 2018.3 OOC synthesis | 0 errors；timing gate FAIL | Step-4 hierarchy可對XC7Z020綜合，但尚未取得100 MHz timing sign-off |
| Post-synthesis timing | WNS -2.863 ns；估計critical delay 12.863 ns | 最差路徑位於凍結subsystem內，從job controller `row_tile_q[2]`到memory-service DSP `requested_weight_word1/CEC` |
| Post-synthesis resources | 21,050 LUT；24,109 FF；69 RAMB36；3 RAMB18；37 DSP | Step-4 OOC資源快照；不是post-route或完整PS Block Design數字 |
| Internal timing coverage | 0 no-clock pins；0 unconstrained internal max-delay pins | 內部同步路徑已受100 MHz clock約束；259個top I/O尚無input delay，必須由未來BD/介面constraint處理 |

完整原始報告保存在 `rtl/reports/accelerator_top_step4/`。目前不把 OOC
post-synthesis 負 slack 解讀為板上失敗：凍結 subsystem 的既有證據曾在
post-synthesis 為負、post-route 轉為 WNS +0.242 ns；但在 Step 4 完成 full
implementation 前，也不能宣稱 accelerator top 已達 100 MHz。

## 本步驟刻意保留的外部邊界

- stage 0 fullband ingress 與 stages 3/6/9 的 dense-feature dispatcher；
- stages 5/8/11 coefficient store、CDF operand routing 與 DeepFilter datapath；
- final output buffer／AXI4-Stream；
- AXI4-Lite control/status register decode；
- PS7、HP/GP interconnect、AXI BRAM Controller、DMA、reset/CDC 與 pin/physical
  constraints；
- full place-and-route、v4 bitstream 與 PYNQ-Z1 functional test。

因此目前已完成的是「FSM＋frozen PE/memory＋LayerNorm mailbox 的 Step-4 RTL
整合與原子資料契約」，不是完整音訊推論 overlay。

## 下一步

1. 實作 feature dispatcher，把 782-byte buffer 映射至 stages 3/6/9 的
   branch/context/source request，並補 fullband stage-0 ingress。
2. 實作 subband coefficient store、DeepFilter lifecycle 與 final output egress。
3. 建立 AXI-Lite control/status、PS7 Block Design 與完整 implementation；以
   post-route WNS/WHS、DRC、unrouted nets 做 100 MHz gate。
4. 只有在 matching v4 BIT/HWH 產生後，才 program PYNQ-Z1，量測 mailbox、DDR、
   frame completion、latency/RTF 與錯誤復原。
