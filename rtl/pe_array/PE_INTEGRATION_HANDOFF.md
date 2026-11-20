# PE subsystem integration handoff

## 文件用途與正式狀態

本文件提供 Controller/FSM 與 Memory subsystem 組員進行 PE 整合時的人類可讀
交接資訊。PE-side arithmetic、streaming leaf 與 structural integration wrapper
已完成正式 promotion；production Controller/FSM、Memory/AXI、parameter/state/
coefficient storage 與 spectrum-history storage 尚未實作或驗證。

正式且唯一的 PE integration top 是：

```text
rtl/pe_array/baseline/v1/rtl/top/pe_array_datapath.v
```

`rtl/pe_array/baseline/v1/` 是已驗證、已接受且凍結的正式 baseline，只能作為
read-only integration dependency。Controller/FSM 與 Memory 必須適配目前
`pe_array_datapath.v` interface，不得為了方便整合而修改 baseline。如果發現
不相容，立即停止、回報原因並等待明確批准；即使未來批准修改，也必須建立新
checkpoint 與新 baseline version，不得覆寫 `baseline/v1`。

完成狀態應以 `baseline/v1/MANIFEST.md`、`HANDOFF.md` 與最新明確批准為準。
`spec/MODULE_DEVELOPMENT_PLAN.md` 仍是架構 invariant 的來源，但其中部分
module-status 文字早於目前 promotion，不可用來推翻正式 manifest。

## Baseline 組成

Baseline v1 包含十一個 arithmetic/functional leaves：

1. `pe_requant_lane`
2. `pe_local_requant_bank_4lane`
3. `pe_hybrid_mac`
4. `pe_sigmoid_lut_255`
5. `pe_gate_postprocess`
6. `pe_membrane_sequencer`
7. `pe_output_serializer`
8. `pe_shared_requant_engine`
9. `pe_spike_decision`
10. `pe_active_index_writer`
11. `pe_cdf_sequencer`

另有一個獨立分類的 integration wrapper：

- `pe_array_datapath`

Wrapper 不是第十二個 arithmetic leaf。它只負責 physical-resource ownership、
mux/demux、tag adaptation、atomic join/fork、collector、serializer context、
outstanding/drain accounting、protocol assertion 與 overflow aggregation；不包含
layer/tile/workload controller FSM 或 Memory RAM/subsystem。

## Physical datapath

```text
GSU / QBN flow

Controller + parameter/state providers
        |
        v
  RAW / GATE commands
        |
        v
 [16 x Hybrid MAC] <-------------------------------+
        |                                           |
        v                                           |
 [1 x 4-lane Local RQ Bank]                         |
        |                                           |
        v                                           |
 [1 x Gate Postprocess] ---> i_t collector          |
        |                                           |
        +--> [1 x Sigmoid LUT] ---> lambda collector|
                                      |              |
                                      v              |
                         [Membrane Sequencer] -------+
                                      |
                                      v
                           [Output Serializer]
                                      |
                    scalar + parameter atomic join
                                      |
                                      v
                         [1 x Shared RQ, QBN]
                                      |
                          exactly-once two-way fork
                             /                 \
                    dense state write    Spike Decision
                                              |
                                      Active Index Writer
                                              |
                                      active-index command

Linear / CDF flow

[same 16 x Hybrid MAC] -> [same Serializer] -> [same Shared RQ, Linear]
        -> coefficient_* -> external coefficient staging/reshape
        -> CDF tap packets + external spectrum history
        -> [CDF Sequencer] -> [same 16 x Hybrid MAC]
        -> signed INT32 complex group result
```

## Controller/FSM interface 分類

方向以 `pe_array_datapath` 為準。資料 payload 可由 Memory provider 供應，但
Controller 負責排程、owner 協定與 transaction sequencing。

| 分類 | Controller 提供給 PE | Controller 接收/監看 | 整合責任 |
| --- | --- | --- | --- |
| Clock/reset | `clk`, `rst_n` | — | 系統 reset 與 clock domain 必須一致 |
| Compute owner | `raw_owner_request`, `gate_owner_request` | corresponding grants、`compute_owner`, `compute_idle` | request 是 level；一次只能有一個 owner request |
| RAW/GATE Hybrid PE | `ctrl_pe_acc_clear`, `ctrl_pe_acc_enable`, mode、operand、gate、spike-enable、DIRECT value | `pe_accumulator`, `pe_overflow` | 依 owner 與 phase 發命令；不可在 result reservation/stall 時覆寫 live accumulator |
| Gate context | `gate_tile_*` | `gate_tile_ready`, `gate_collect_complete` | 一個 16-lane tile context；mask 必須非零且 tags/mask 在 transaction 中穩定 |
| Gate Local RQ | `gate_rq_*` | `gate_rq_ready` | 依下述 INPUT→RECURRENT paired schedule 發送四-lane packets |
| Gate bias | `gate_bias_*` | `gate_bias_ready` | 只與 matching RECURRENT RQ response atomic join |
| Sigmoid config | `sigmoid_cfg_start_*`, config bytes | ready/done/`sigmoid_table_valid` | 只能在 compute owner 為 NONE、無其他 owner request 時載入 |
| Membrane job | `membrane_start_valid`、`u_prev`、cx/cell RQ params、base index、logical-last | ready/busy/done/phase | i_t、lambda、lane mask、tags 由 wrapper gate collectors 提供 |
| Linear tile | `linear_tile_*` | `linear_tile_ready` | RAW accumulator 穩定後交給 serializer；metadata 必須保持至 handshake |
| CDF job | `cdf_start_*` 與 tap scheduling | ready/busy/done/phase、active tap index | 必須保持 `cdf_start_valid`，讓 leaf 在 handshake 前先提出 CDF owner request；取得 grant 後才會 ready/accept；外部逐 tap 提供 memory payload |
| Diagnostics | — | all derived-idle/outstanding、`overflow_any`, `protocol_error` | `protocol_error` 視為 integration contract violation；不得忽略 |

## Memory subsystem interface 分類

| 資料類別 | PE 端 interface | Memory 端責任 |
| --- | --- | --- |
| Gate/RAW operands與params | controller PE command payload、`gate_rq_multiplier/shift`、`gate_bias_*` | 保存並依 Controller 排程提供 weight/operand/RQ multiplier/shift/bias |
| Sigmoid table | `sigmoid_cfg_*` byte stream | 保存或載入 table image；遵守 start/data ready-valid |
| Previous membrane state | `membrane_u_prev` | 讀出 matching 16-lane signed INT8 state tile |
| Membrane RQ params | `membrane_cx_*`, `membrane_cell_*` | 提供 matching per-lane multiplier與shift |
| Shared-RQ params | PE 輸出 `rq_param_query_*`；Memory 回傳 `rq_param_*` | 依 op-kind/index/tag 提供 multiplier、shift、bias；回應必須精確 match |
| Dense QBN state | `state_write_valid/ready/value/index/tag/last` | 每個 QBN scalar exactly-once 寫入 dense state storage，並提供 backpressure |
| Active index | `active_cmd_valid/ready/write/index/tag/finalize` | 擁有 active count、write pointer、capacity/full 與 index storage；用 ready 回壓 |
| Linear coefficient | `coefficient_valid/ready/value/index/tag/last` | 保存飽和於 `-127..127` 的 signed INT8 scalar，依 index/tag reshape/stage 為 complex filter coefficients |
| CDF history/taps | `cdf_tap_*`, Xr/Xi/Cr/Ci buses | 擁有完整 coefficient storage、noisy-spectrum temporal history 與 causal zero padding；active bin 的 Xr/Xi/Cr/Ci 必須在 `-127..127`，不得提供 `8'h80` |
| CDF result | `cdf_result_valid/ready`、real/imag與metadata | 接收每組最多八 bins 的 signed INT32 complex result；PE 不做 RQ/saturation |

## Owner、grant 與 phase-switch 規則

`compute_owner[3:0]` 是 registered one-hot lock：

| Value | Owner | Physical compute resource |
| --- | --- | --- |
| `4'b0000` | NONE | 無 compute owner |
| `4'b0001` | RAW | 16 Hybrid PEs；Linear 時再使用 serializer/Shared RQ |
| `4'b0010` | GATE | 16 Hybrid PEs、Local RQ、Gate Postprocess、Sigmoid/collectors |
| `4'b0100` | MEMBRANE | 同一批 16 Hybrid PEs、Local RQ、Gate Postprocess、serializer |
| `4'b1000` | CDF | 同一批 16 Hybrid PEs |

必須遵守：

- 所有 grant 都是 all-or-none；wrapper 不做 priority arbitration。
- NONE 時若同時出現多個 owner requests，不會選 winner，並會形成 protocol
  error。Controller 必須先等 `compute_idle`，再只 assert 一個 request。
- `raw_owner_request` 與 `gate_owner_request` 由 Controller 直接控制。
- Membrane start 先由 wrapper 接受，之後 leaf 才提出 Membrane owner request。
- CDF 不同：held `cdf_start_valid` 在 start handshake 前就形成 leaf 的 CDF
  owner request；它在 NONE 時必須是唯一 request。取得 CDF grant 後，
  `cdf_start_ready` 才可能為 1 並接受 job。
- request 必須保持到 grant；工作完成且所有送入 valid 已撤除後才 deassert。
- 任兩個 compute owners 的切換必須經過至少一個 NONE state。
- owner release 使用 handshake-derived outstanding、held-valid 與 pipeline-empty
  條件；不得用固定 latency counter 猜測 drain。
- RAW release 需要 PE command/pipeline drain 且 `linear_tile_valid=0`。
- GATE release 需要 Hybrid、Local RQ、Postprocess、Sigmoid 全部 drain，沒有
  half-pair、held gate RQ/bias，且 collector 已完成、已交給 membrane 或無 context。
- MEMBRANE release 需要 leaf request 結束、Hybrid/Local RQ/Postprocess drain，
  且沒有 held membrane result。
- CDF release 需要 CDF command pre-pipeline與Hybrid drain，且沒有 held CDF result。
- 下游 stall 時 valid/payload 必須保持；任何仍被 release predicate 保護的
  held result 或 outstanding transaction 未完成前，不得切換其 owner。

`compute_idle` 只表示 compute-owner/acquire domain 可安全取得，不代表整個
serializer/Shared-RQ/QBN fork 已排空。Layer/frame barrier 必須同時檢查
`compute_idle`、
`serializer_idle`、`shared_rq_idle`、`qbn_fork_idle` 及相關 outstanding
輸出。

## Gate paired schedule

Local RQ 的 canonical tag width 是 20：

- Gate：`{gate, component, group[1:0], user_tag[15:0]}`
- Membrane：`{1'b0, membrane_tag[18:0]}`

Gate Postprocess 與 Sigmoid tag width 是 18：

- `{group[1:0], user_tag[15:0]}`

每一個 gate/group 必須嚴格送：

```text
INPUT(component=0, gate, group, lane_mask, tags)
  -> RECURRENT(component=1, same gate, same group, same lane_mask, same tags)
```

不可在 pair 中間插入另一個 gate/group。INPUT 先建立 pending half；matching
RECURRENT 才完成 pair。Active-lane tags 也必須相同，雖然 tag comparator 不在
ready critical path，仍是強制 protocol check。Bias 僅在 RECURRENT response
到達時 atomic join，並且 gate/group/lane-mask/tags 必須 match；bias provider
必須在 `valid && !ready` 時保持所有欄位穩定。

`gate_rq_gate=0` 的 postprocess result 進入 i_t collector；
`gate_rq_gate=1` 的 result 經 Sigmoid 後進入 lambda collector。所有 active
lanes 的 i_t 與 lambda 都收齊後，`gate_collect_complete` 才能成立並交接
Membrane。

## Data ownership boundary

| 資料 | PE wrapper 保證 | 外部 owner |
| --- | --- | --- |
| Dense state | 每個 QBN scalar 產生 exactly-once state-write branch；value/index/tag/last 對齊 | Memory 保存 state RAM、addressing與容量 |
| Spike/active index | QBN-only signed predicate為 `state_q >= 0`，零會 spike；普通 non-spike不產生 command，terminal non-spike仍 finalize，terminal spike atomic write+finalize | Memory 保存 active-index storage、active count、write pointer與full state |
| Linear coefficient | Shared RQ `op_kind=Linear` 只輸出飽和於 `-127..127` 的 signed INT8 scalar，不進 spike path | Memory/integration reshape、stage並保存 complex coefficients |
| CDF history | Sequencer只消費目前 group/tap 的 Xr/Xi/Cr/Ci 並輸出 signed INT32 real/imag；active operands 合法範圍為 `-127..127`，`8'h80` 非法 | Memory 保存 spectrum temporal history與完整 coefficient set，提供 causal zero padding，並依 `tap_index=0..order-1` oldest-to-newest 送入且匹配 `cdf_active_tap_index` |

## Valid/ready 與 atomicity

- 所有真正 stream 只在 `valid && ready` 的 edge 轉移一次。
- Producer 在 `valid && !ready` 時必須保持 payload、index、tag、mask、last、
  op-kind 與其他 metadata 完全穩定。
- `rq_param_query_*` 是 combinational look-ahead key，不是已接受的 request。
  Serializer scalar 與 matching parameter 只在兩邊 valid 且 Shared RQ ready 時
  atomic accept。
- Shared RQ 的 `op_kind=0` 是 QBN，`op_kind=1` 是 Linear；output 依 op-kind
  demux，Linear 絕不可進 spike path。
- QBN 使用 one-entry holding register 加 state/decision pending bits。Dense state
  write 與 decision 各 exactly once，decision 不得早於 matching state write；
  兩個 sink 可獨立 backpressure。
- Serializer 依 ascending lane order 輸出並跳過 inactive lanes；index 是
  base-index + lane。`last` 只表示 logical vector 最後一個有效 neuron。

## 已接受的 verification 與 implementation evidence

Connected integer/Python reference與 XSim bit-exact verification PASS。保留的
connected run 完成於 2,330 cycles，觀察到：

- 11 dense-state outputs；
- 6 active-index writes；
- 12 Linear/CDF coefficient outputs；
- 23 Shared-RQ parameter handshakes；
- 8 gate-bias handshakes。

測試涵蓋 GSU→Membrane→QBN→Spike→Active Index 與
Linear→Shared RQ→behavioral coefficient staging→CDF，並在 randomized
parameter delay與下游 backpressure 下檢查 owner transitions。這是 behavioral
Controller/Memory BFM 的 connected PASS，不代表 production FSM/Memory、bitstream
或 board 已驗證。

Hierarchy與 post-route resource summary：

| Item | Result |
| --- | ---: |
| `pe_hybrid_mac` | 16 |
| `pe_local_requant_bank_4lane` | 1 |
| Total physical `pe_requant_lane` | 5（Local RQ 內4 + Shared RQ 內1） |
| `pe_shared_requant_engine` | 1 |
| DSP48E1 | 36 |
| RAMB18E1 | 2 |
| Total LUT | 10,225 |
| Total FF | 10,573 |

100 MHz / 10.000 ns routed OOC 現況：

- internal register-to-register setup WNS = **+0.727 ns，PASS**；
- internal register-to-register hold WHS = **+0.056 ns，PASS**；
- overall setup WNS = **+0.254 ns**；
- standalone OOC boundary hold WHS = **-1.368 ns，尚未 clean**；
- Vivado `timing_constraints_met=0`，因此不可宣稱完整 100 MHz top timing
  closure。

**200 MHz 不是目前 connected PE subsystem 的 verified operating point。**

## 正式整合前的下一步

Controller 與 Memory 組員應各自先對
`baseline/v1/rtl/top/pe_array_datapath.v` 做 interface mapping/review，明確
對應每個 ready/valid channel、owner transition、parameter query、writeback 與
storage boundary。雙方確認 mapping 後才開始各自 RTL integration。

Production FSM 與 Memory 接上後，必須重新執行：

1. system-level self-checking XSim，並與 Python/integer golden bit-exact 比對；
2. random backpressure、owner-switch、terminal/finalize 與 error stress；
3. final hierarchy/resource duplication check；
4. top-level synthesis、place-and-route；
5. 完整 setup/hold timing closure。
