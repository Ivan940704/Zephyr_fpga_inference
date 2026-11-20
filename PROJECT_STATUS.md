# Zephyr FPGA inference 專案進度

> 團隊進度參考頁。整體階段或證據有實質變化時可更新；一般 checkpoint 不再
> 強制同步本頁、task 或 handoff。每次完成的更新只要求留下 Git commit。

- 最後更新：2026-09-09（Asia/Taipei）
- 最新profiling v2 checkpoint：hardware baseline
  `ec457b1cb1e025ccc38944c912145cd07c5625d5`完成hardware-acknowledged reset與
  fail-closed host recovery；fresh Vivado 2018.3 full-design post-route為standard WNS
  `+0.264 ns`、250 ps guardbanded WNS `+0.014 ns`、50 ps hold-guardband WHS
  `+0.006 ns`、raw hold `+0.056 ns`，0 timing/routing/blocking-DRC failure。資源為
  27,761 LUT、38,456 FF、77.5 BRAM36 equivalent、46 DSP，全部低於80%。Matching
  BIT/HWH SHA-256分別為`6521bdca…9aeaeb`與`6538bd37…1476bc`，image ABI為
  `0x00040002`。
- Latency scaling feasibility實驗已完成固定5檔同輸入板端A/B。PC預算與PYNQ frontend
  均5/5 PASS，共46,274 frame-runs；PC預算版weighted frame latency 11.147 ms，較
  control 11.062 ms慢0.773%，board-loop／end-to-end RTF也慢1.138%／1.257%。完整
  float NPY bundle load共7.411 s，比PYNQ STFT compute的6.943 s多6.739%，因此目前
  方法功能可行但沒有觀察到latency改善；每模式只有一次五檔run，未建立統計退化。
  兩端FFT浮點尾數不bit-exact；11,846,144個spectrum
  INT8元素全同，1,480,768個fullband INT8只有1個差1 LSB，enhanced WAV為2/5 SHA
  相同，audio-weighted SNR improvement僅差+0.0215 dB。10次fresh reset、30個DMA
  pre-stop/error gate與10份final fault/control/DMA gate皆PASS；測試後cleanup reset為
  epoch 5→6，三DMA停止且0 error。32-lane Hybrid MAC
  bank的XSim 64/64結果PASS；XC7Z020 125 MHz OOC route使用
  2,622 LUT、2,145 FF、32 DSP、0 BRAM，setup WNS +0.424 ns、內部reg-to-reg hold
  +0.047 ns、0 routing error。OOC外部邊界hold仍為-1.226 ns，且production 16-PE
  controller/memory未改，不能宣稱完整32-PE或full-system 125 MHz。現有full design
  在100 MHz加250 ps guardband只剩+0.014 ns WNS，netlist不變直接125 MHz估計
  -1.736 ns。PS7 HP port固定64 bit；128-bit AXIS對目前payload最多省1.312 us/frame，
  不會讓DDR頻寬加倍，因此本輪不改production interface。完整證據與行程見
  [Latency scaling feasibility experiment](docs/experiments/LATENCY_SCALING_32PE_EXPERIMENT.md)。
- 目前階段：**ec457b1已在PYNQ-Z1 Linux完成correctness/profile/runtime matrix與100檔
  音訊；所有功能、安全reset與DMA gate PASS，但整體RTF仍大於1，endurance與physical
  power尚未完成。** Experiment matrix包含9次correctness/profile與40次30秒benchmark，
  合計150,040 frames；49次pre-run reset皆epoch `+1`，三DMA皆先停止且0 error，所有
  integer frozen-oracle陣列完全相等。最快已測設定
  `bulk/native/cache/no-diagnostics/busy-poll`平均frame latency 12.667 ms、frame-compute
  RTF 1.584、board-loop RTF 3.031、end-to-end RTF 3.146、41.247 frames/s，因此仍非
  real time。
- 100檔PTQ clean/noise/noisy campaign為100/100 PASS，共426,196 frames與
  3,408.768 s evaluated audio。每檔執行前100次reset皆epoch `+1`且DMA停止／0 error；
  所有輸出最終first-fault/control-error/DMA-error皆為0。Weighted mean frame latency
  11.055 ms，aggregate frame-compute／board-loop／end-to-end RTF為
  1.382／2.739／2.853。平均SNR由7.092提升到14.781 dB，平均改善+7.688 dB
  （95% bootstrap CI +6.806..+8.556 dB；2% clips regression）；平均SI-SDR改善
  +7.454 dB。PESQ/STOI僅因板上未安裝`pesq`／`pystoi`而BLOCKED，不由其他指標推定。
- 代表性`fileid_081`的4,246-frame raw PL profile通過cycle conservation，request sparsity
  與MAC skip皆為77.115%，parameter-byte savings為55.179%；PL latency mean/p95/p99為
  10.484/11.411/12.282 ms。一次541 ms max來自host scheduling outlier，故保留raw JSONL
  並與同檔非profile max 18.121 ms分開解讀。Endurance依外部暫停要求停止；最後durable
  checkpoint為179,000 frames／3,265.110 s、0 frame-ID discontinuity，狀態仍是
  `RUNNING`而非PASS。Cleanup已完成epoch 153→154安全reset，三DMA停止且0 error，
  未送出recovery inference frame。
- 同一ec457b1 route的Vivado vectorless power estimate為1.589 W total、1.443 W dynamic、
  0.146 W static、43.3 C、Medium confidence；無SAIF/VCD且板上沒有rail sensor，不能當成
  physical power。實體功耗仍需外接校準功率計與同步idle/load trace。
- CP7 registered-write sparse memory是目前parameter-memory production baseline。1,053,056-byte v4
  image使用一次性的2,040-byte global sigmoid LUT；dense模式載入完整stage，sparse
  模式依context union只scatter載入eligible weights，mandatory matrices／parameters
  仍完整resident。CP7將byte geometry及64-bit parameter writes註冊化；凍結的connected
  XSim以dense與sparse各兩frame跑完12 stages與60 jobs，共12,450,566 checks PASS；
  前一版isolated subsystem 100 MHz route為WNS
  +0.151 ns、25,096 LUT、27,527 FF、68 RAMB36、2 RAMB18與40 DSP。這不是完整top
  timing或板測結果。
- 4 KiB `layernorm_mailbox`是PS preprocessing production候選：兩個64-byte FB
  output slots與兩個782-byte SB input slots，standalone XSim與100 MHz OOC已通過
  （1,120 LUT、801 FF、1 RAMB36、WNS +1.647 ns）。Step-4 adapter已把它接到FSM
  與subsystem coefficient stream，並在完整782 bytes緩衝及slot release後才喚醒FSM；
  full BD已接AXI BRAM Controller，AXI4-Lite control也提供held claim/commit/release命令；
  PYNQ 3.0.1已用bulk MMIO、ARM barrier與native LayerNorm連續通過100檔音訊。
  Experiment matrix的`bulk/native/cache/no-diagnostics` mean mailbox為1.491 ms，
  相較歷史scalar/NumPy 16.952 ms明顯改善；IRQ取代polling仍未量測。
- Parameter BRAM full-BD implementation與artifact checkpoint已完成
  [硬體／軟體設計與驗證計畫](docs/memory/PARAMETER_BRAM_BOARD_BRINGUP_PLAN.md)：
  `memory_service_axil`、single-clock top、13筆real-v3 readback vectors、AXI-Lite
  integration TB、PYNQ-Z1 BD Tcl及PYNQ driver dry-run均已落實。Python 18/18與
  Windows Vivado real-v3／相關memory XSim通過；PYNQ-Z1 preset BD從乾淨temp完成
  synthesis、opt/place/route，post-route WNS +0.964 ns、WHS +0.019 ns、0 failing
  endpoints與0 unrouted nets。完整BD為3,814 LUT、5,218 FF、1 DSP及73 RAMB36+
  1 RAMB18，所有資源低於80%線。Gate為PASS WITH RISKS：Vivado 2018.3 preset的
  DDR DQS critical warnings已有本機來源／schema證據可帶風險接受，本次Icarus則因
  executable不存在未重跑。2026-09-03另由frozen commit `78c86f3`的同版hardware
  inputs乾淨重建，成功產生matching BIT/HWH/LTX與SHA-256 manifest；fresh sign-off仍為
  WNS +0.964 ns、WHS +0.019 ns、0 failing endpoints／unrouted／blocking DRC。
  但本次沒有明確PYNQ-Z1連線endpoint，依安全契約在program前停止，板測結論為
  **BLOCKED**；HW ID、Stage 2 counters、5筆readback與release/cleanup均未取得。
  這些BIT/HWH/LTX使用歷史v3 service，不是Sequential v4 accelerator artifact，
  不得拿來宣稱新baseline已上板。
- `rtl/pe_array/baseline/v1/MANIFEST.md`與最新handoff認定的formal PE baseline為
  11個 arithmetic/functional leaves，加上一個獨立分類的
  `pe_array_datapath` integration wrapper。158/158 archive checksum已於
  2026-09-03重跑通過。Connected wrapper的100 MHz routed OOC為10,225 LUT、
  10,573 FF、36 DSP、2 RAMB18；internal setup/hold通過，但standalone input-boundary
  hold未clean，因此不可宣稱完整top timing closure或connected 200 MHz。
- 單一bit-exact GSN/GSU neuron cell另有672/672 XSim與5 ns OOC證據
  （1,172 LUT、1,484 FF、5 DSP、1 BRAM18、WNS +0.263 ns），但它從INT32 matrix
  accumulator開始，只是驗證核心，不屬formal PE baseline，也不得複製320份。
- global `fsm.v`已對齊sparse CP6 reset-only fatal contract：sparse mode只在frame接受時
  取樣並穩定驅動所有stage；success-only `stage_load_done`未assert時的
  `stage_load_error`也會立即進入`ERR_MEMORY`。ERROR只能由協調reset
  離開、held-high `start`不會重啟第二frame、IDLE既存PE fault會阻止啟動。shared-engine
  接線用真實v4 image跑完兩frame：2,385,005 checks、24次stage load、6個FB jobs、
  54個SB jobs及101,446筆sparse requests。FSM-only XC7Z020 100 MHz OOC為163 LUT、
  80 FF、WNS +4.135 ns。`parallel_subbands=0`是唯一production模式；PS mailbox
  已在top以atomic adapter接線，DeepFilter與final-result stream亦已整合。
- 後續整合必須先讀
  [Sparse accelerator-top integration](docs/memory/SPARSE_ACCELERATOR_TOP_INTEGRATION.md)
  、[accelerator-top handoff](docs/memory/HANDOFF.md)
  、[Step-4設計與驗證紀錄](docs/memory/ACCELERATOR_TOP_STEP4.md)
  與[compile/source manifest](docs/memory/MANIFEST.md)。
  舊parameter-memory ping-pong contract、RTL、TB、reference、runner與reports已集中到
  `archive/parameter_memory_ping_pong/`，保留研究provenance但禁止進production compile。
- 九個tracked v3檔案暫時保留但不進production compile：v4 generator仍直接重用v3
  packing implementation，v4 image test仍以frozen v3 artifacts做逐值migration oracle，
  歷史parameter-BRAM bring-up與BIT/HWH/LTX provenance也需要它們。安全刪除前必須先
  抽出version-neutral generator library、替換同等強度的v4 oracle，並裁決舊板測stack。
- 原始設計簡報：[音訊降噪系統整合報告](docs/音訊降噪系統整合報告.pdf)
- 簡報 SHA-256：`d44675cc82b0464a1842f9633e62836f345a01306474097eb57a6636e06aea56`
- RTL 使用說明：[rtl/README.md](rtl/README.md)
- 團隊工作方式：[TEAM_COLLABORATION.md](TEAM_COLLABORATION.md)
- PYNQ-Z1 feasibility gate：[docs/PYNQ_Z1_FEASIBILITY_CHECKLIST.md](docs/PYNQ_Z1_FEASIBILITY_CHECKLIST.md)

## 版本歷史

- 2026-09-09：取得授權後完成固定5檔同輸入frontend A/B，PC預算與PYNQ-side control
  均5/5 PASS，共46,274 frame-runs。PC預算版weighted frame latency 11.147 ms，較
  control 11.062 ms慢0.773%；board-loop／end-to-end RTF慢1.138%／1.257%，float NPY
  load亦比PYNQ STFT compute多0.468 s，因此目前方案沒有latency收益。所有spectrum
  INT8相同，fullband INT8僅1個元素差1 LSB；audio-weighted SNR improvement差
  +0.0215 dB。Raw evidence在PYNQ的`/home/xilinx/zephyr_latency_32pe_20260908/results/`，
  repo內保留checksummed摘要與可重現比較程式。

- 2026-09-08：完成latency scaling第一輪host/OOC feasibility。新增checksummed host
  STFT+magnitude bundle與PYNQ fail-closed loader，固定5檔host generation平均0.0681 s，
  Python 2/2 PASS。32-lane Hybrid MAC bank在Vivado 2018.3 XSim驗證64/64結果；
  125 MHz OOC post-route為2,622 LUT、2,145 FF、32 DSP、setup WNS +0.424 ns、內部hold
  +0.047 ns與0 routing error，同時保留-1.226 ns OOC boundary hold限制。由fileid_081
  profile推估32 PE+125 MHz的PL latency為6.832 ms（70% compute可平行）至6.007 ms
  （理想100%）；此為分析估計，不是full design或板測。128-bit stream因PS7 HP仍為
  64 bit，理論上限僅1.312 us/frame，故未改production interface；完整系統125 MHz亦
  尚未收斂；固定5檔板端precomputed run在該日尚未執行，已於2026-09-09完成。

- 2026-09-08：完成ec457b1 PYNQ-Z1 runtime campaign與100檔音訊。9次correctness/profile
  加40次benchmark共150,040 frames全部PASS；49次reset皆硬體epoch `+1`且DMA安全停止。
  100檔共426,196 frames／3,408.768 s evaluated audio，100/100 PASS；weighted mean frame
  11.055 ms，aggregate frame/board-loop/end-to-end RTF 1.382/2.739/2.853，平均SNR改善
  +7.688 dB、SI-SDR改善+7.454 dB。代表性PL profile量到77.115% MAC skip與55.179%
  parameter-byte savings。Endurance僅保存179,000-frame／3,265.110 s暫停checkpoint並安全
  cleanup，不宣稱PASS；physical power仍BLOCKED。完整原始輸出保存於WSL
  `/home/ivanhuang/zephyr_board_results/ec457b1/`，Git保留可重算摘要與100份metrics。

- 2026-09-08：完成profiling v2 timing closure、release與JTAG Stage 2。將duplicated
  64-bit snapshot bank／wide mux替換成32-bit工作counter與194-cycle serialized
  distributed-RAM snapshot，保留192-word 64-bit host ABI。Fresh Vivado 2018.3 full
  route為standard WNS +0.253 ns、250 ps guardband WNS +0.003 ns、50 ps hold WHS
  +0.016 ns、0 failing endpoints，LUT／FF相對失敗baseline減少1,565／8,335。由同一
  passing checkpoint產生BIT SHA-256 `52d8f029…97f289`與matching HWH；具名PYNQ-Z1
  JTAG program及DONE/CRC/IDCODE/security PASS，AHB-AP0唯讀image `0x00040002`與packet
  ABI PASS。完整host suite 197 passed，100-triplet輸入與所有board runner已備妥；但
  無PYNQ Linux endpoint與外接功率計，因此不宣稱v2 inference、counter、RTF、latency、
  physical power或endurance。Vivado default-activity estimate為1.610 W total、1.463 W
  dynamic、0.147 W static、43.6 C、Medium confidence。

- 2026-09-07：完成三筆PTQ語音／噪音資料的長序列PYNQ-Z1 inference。實際資料夾包含
  100組matched triplets，本次固定選file ID 8／54／18覆蓋低、中、高input SNR；同一
  release image連續跑完13,085 frames，frame ID 33..13,117無缺漏，最終control、mailbox、
  DMA皆無錯。三筆SNR改善+18.769／+6.288／+0.548 dB，concatenated改善+14.019 dB；
  weighted mean frame 26.368 ms、board-loop RTF 4.828，仍未達real time。新增external
  16 kHz PCM runner、compact timing/boundary sparsity證據與enhanced WAV。相同routed DCP
  的Vivado power estimate為1.599 W total、0.147 W accelerator（Medium confidence）；
  因PYNQ Linux沒有rail sensor，能量只以estimate×measured time呈現，不宣稱實測功耗。

- 2026-09-07：完成corrected Sequential-v4 accelerator的production release與實板
  inference。Baseline `1cb0724`加入分離CX／CELL raw phase及response backpressure，
  connected XSim兩個harness與65項host RTL tests通過。Fresh Vivado 2018.3 full route為
  standard setup WNS +0.263 ns、250 ps guardband WNS +0.013 ns、50 ps hold-guardband WHS
  +0.014 ns、raw hold +0.064 ns，routing／coverage／CDC／blocking DRC與資源gate均PASS。
  Release BIT SHA-256為`2f6e7cc9…899aa`；具名PYNQ-Z1 target的program/DONE/error check
  PASS。板上以v4 image跑完frame ID 0..32，16,896個accumulator分量與NumPy oracle完全
  一致；deterministic 4,096-sample fixture的SNR提升+3.069 dB。平均30.030 ms/frame、
  sequential compute RTF 3.754，故功能部署完成但real-time throughput仍未達標。
  診斷另確認DMA enabled時重複JTAG重配會使PS/HP transaction state不同步；正式流程固定
  為clean PS boot後只program一次再開始traffic。

- 2026-09-07：完成首次full accelerator artifact與PYNQ-Z1燒錄。Baseline `eb496dd2`
  的fresh full route達standard setup WNS +0.301 ns、250 ps guardband WNS +0.051 ns、
  50 ps hold-guardband WHS +0.012 ns及raw hold +0.062 ns；route、coverage、CDC、blocking
  DRC與資源gate全數PASS。由同一DCP/project產生4,045,679-byte BIT與matching HWH，
  manifest固定BIT SHA-256 `33afbe9c…a1a420`。Vivado只選具名Digilent target
  `003017B78476A`並成功program `xc7z020_1`；三種DONE為1且CRC/IDCODE/security error為0。
  XSCT AHB-AP0唯讀確認image ABI `0x00040001`及packet sizes。因三個DMA皆Halted但Idle=0，
  未進行任何MMIO write/reset/traffic；persistent flash、PYNQ runtime、DMA/mailbox、golden、
  performance/power/audio仍未驗證。

- 2026-09-07：完成DMA-safe software reset與夜間full implementation。BD將software
  data reset限制在custom accelerator，DMA、mailbox AXI controller與HP0..HP3 interconnect
  留在system reset；RTL新增persistent quiesce fence、兩拍registered safe proof、reset
  pending/epoch與拒絕碼，host helper依序ABORT、停止三個DMA、確認Halted+Idle、quiesce、
  reset一次並核對epoch/ABI。Control與top XSim、BD validation及host tests通過。Baseline
  `2293a02`的fresh Vivado 2018.3 full route為56,285/56,285 nets、standard WNS +0.197 ns、
  250 ps guardband WNS -0.053 ns、50 ps hold-guardband WHS 0.000 ns、raw hold +0.050 ns；
  DRC 0 Error/0 Critical/115 Warning，methodology 5 Warning。Setup gate短少53 ps，故沒有
  BIT/HWH、program或board evidence。
- 2026-09-07：執行setup工程裕量attempt 2。fresh Vivado 2018.3 allowlist build在
  Explore placement／routing與前後route physical optimization期間加入額外250 ps setup
  uncertainty，完成後恢復normal uncertainty再保存報告。標準100 MHz setup WNS由
  +0.160 ns改善為+0.199 ns，但guardbanded WNS為-0.051 ns，未達固定+0.250 ns目標；
  50 ps hold guardband仍以WHS +0.005 ns通過，raw hold margin +0.055 ns。route、coverage、
  CDC、blocking DRC與<80%資源gate通過；依fail-closed契約停止在production BIT/HWH前。
- 2026-09-07：解決full-design hold margin。implementation在placement／routing前對
  `clk_fpga_0`加入50 ps hold uncertainty guardband；fresh Windows Vivado 2018.3
  clean-allowlist build的guardbanded WHS為+0.007 ns，移除guardband量測的raw margin為
  +0.057 ns，較先前+0.014 ns增加43 ps。Setup WNS同時改善至+0.160 ns，TNS／THS與
  failing endpoints皆為0；55,958/55,958 routable nets完成，0 routing errors、CDC
  safely timed、0 blocking DRC。資源為29,847 LUT、34,927 FF、77.5 BRAM36 equivalent、
  46 DSP。未加入false/multicycle exception，亦未產生BIT/HWH或執行板測。
- 2026-09-07：完成full PYNQ-Z1 accelerator實作。從乾淨baseline `68335d7`重建
  control XSim、BD、global synthesis與完整implementation；第一次Explore route為
  WNS -0.058 ns，Vivado 2018.3 routed-design AggressiveExplore physical optimization
  改善至WNS +0.004 ns／WHS +0.014 ns、TNS/THS 0、setup/hold failing endpoints 0。
  55,976/55,976 routable nets完成，CDC safely timed，DRC與methodology皆0 Error／
  0 Critical Warning；post-route資源為29,810 LUT、34,927 FF、77.5 BRAM36 equivalent
  與46 DSP，均低於80%。Gate為PASS WITH THIN MARGIN：4 ps setup margin與sparse
  memory／job-controller congestion仍是下一個硬體優先項。本checkpoint刻意不執行
  `write_bitstream`、不輸出production HWH且不連板。
- 2026-09-06：完成full Zynq pre-implementation整合。新增AXI4-Lite control/status、
  `accelerator_system_top`與可重建PYNQ-Z1 BD；GP0控制control/mailbox/兩個DMA，HP0..HP3
  分別承載參數、fullband輸入、result輸出與spectrum輸入，四路interrupt接入PS7。
  Reset分為持續存活的control plane與可software重置的data plane。Control XSim於
  1,695 ns PASS、BD validation PASS、Vivado 2018.3 global synthesis 0 errors／0 critical
  warnings，CDC安全且0個unconstrained internal endpoints。Post-synthesis為31,016 LUT、
  35,326 FF、77.5個BRAM36 equivalent、46 DSP，100 MHz WNS -0.321 ns／WHS +0.045 ns。
  本checkpoint刻意未執行opt/place/phys-opt/route、未產生bitstream且未進行板測。
- 2026-09-06：解決sparse accelerator-top 100 MHz timing。原最差路徑由job controller
  `state_q`經`pe_barrier_idle`、global FSM launch與sparse job mapping回到controller
  register CE，共16 logic levels、WNS -1.146 ns。top新增一拍保守barrier sampling，
  external diagnostic維持即時；focused XSim 7/7及既有功能bundle PASS。Fresh Vivado
  2018.3 synthesis WNS為-0.005 ns，routed OOC為WNS +0.115 ns／TNS 0、WHS
  +0.016 ns／THS 0，24,461 LUT、28,443 FF、71 RAMB36、4 RAMB18、46 DSP，0 routing
  errors且內部endpoint完整約束。full PS7/AXI/DMA/CDC implementation與板測仍未完成。
- 2026-09-06：將凍結CP6 `sequential_v4_sparse_memory_subsystem`提升到production
  `accelerator_top`。FSM新增frame-sampled sparse mode，並修正success-only
  `stage_load_done`下的獨立fatal error處理；`tb_fsm`、既有mailbox／dispatcher／
  coefficient-store／DeepFilter regressions及完整sparse top elaboration皆PASS。
  Vivado 2018.3 routed OOC為24,485 LUT、28,417 FF、71 RAMB36、4 RAMB18、46 DSP，
  0 failed/unrouted/partially-routed nets且資源類別低於80%，但100 MHz WNS仍為
  -1.146 ns，所以結論是RTL組合完成、timing closure pending，不生成production
  bitstream或宣稱板測。
- 2026-09-06：新增`sequential_deepfilter_engine`並收回top原本外露的DF lifecycle與
  coefficient read介面。每frame接收512-byte複數INT8 spectrum，保留四個歷史frame，
  對bins 0..31／32..127／128..255執行causal 5/3/1-tap complex MAC，輸出256 beats的
  `{imag_int32,real_int32}`。兩幀synthetic XSim為2,573 checks、2,304 coefficient reads
  PASS；standalone OOC為284 LUT、96 FF、2 RAMB36、6 DSP、WNS +2.542 ns。整合top
  synthesis為21,839 LUT、24,906 FF、71 RAMB36、4 RAMB18、43 DSP、WNS -2.863 ns；
  routed OOC改善到WNS -0.467 ns，0 routing errors且內部endpoint完整約束，但最差路徑
  位於凍結context store，因此仍不進入PS7/DMA bitstream或燒錄。
- 2026-09-06：新增`sequential_df_coefficient_store`，以一個1,152-byte BRAM保存
  stage 5/8/11、4/3/2個context的DF projection；逐byte驗證stage、logical context、
  component/local-bin/tap index、TLAST及frame ownership，並以九位valid bitmap阻止
  不完整係數啟動DF。XSim為64 checks／1,152 coefficients PASS；standalone 100 MHz
  OOC為211 LUT、84 FF、1 RAMB18、0 DSP、WNS +3.709 ns。整合top elaboration PASS，
  資源更新為21,585 LUT、24,809 FF、69 RAMB36、4 RAMB18、37 DSP；100 MHz WNS仍為
  -2.863 ns且最差路徑在凍結subsystem，因此未進入bitstream或燒錄。
- 2026-09-06：新增`sequential_feature_dispatcher`，接收每frame一包64-byte fullband
  AXI4-Stream，並依stage/branch/context/source將fullband或matching 782-byte mailbox
  payload回應給frozen subsystem。XSim為101 checks／6個subband boundary reads PASS，
  existing mailbox adapter與完整top elaboration亦PASS。Vivado OOC synthesis為0 errors，
  資源21,385 LUT、24,726 FF、69 RAMB36、3 RAMB18、37 DSP；100 MHz WNS仍為
  -2.863 ns且最差路徑位於凍結subsystem，因此尚未達timing sign-off。
- 2026-09-05：建立可綜合的`accelerator_top`，連接global FSM、frozen Sequential v4
  PE＋memory subsystem、LayerNorm mailbox及atomic adapter。Step-4 XSim驗證64-byte
  FB publish、PS BRAM 196-word write、782-byte完整緩衝／release、random read
  backpressure、frame advance與錯誤注入，且完整top elaboration PASS。Vivado 2018.3
  OOC synthesis為0 errors，但10 ns timing gate以WNS -2.863 ns FAIL；資源為21,050 LUT、
  24,109 FF、69 RAMB36、3 RAMB18與37 DSP。此結果不是post-route、bitstream或板測。
- 2026-09-05：凍結PE array與Sequential v4 memory為
  `sequential-v4-pe-memory-v1`，獨立25-file checksum為25/25 OK，PE archive為
  158/158 OK，且凍結路徑無RTL diff。修改範圍只在global FSM、TB與整合文件；
  `tb_fsm`、真實v4＋frozen PE/memory雙frame connected harness均PASS，FSM-only
  100 MHz OOC WNS +4.135 ns。Vivado Hardware Manager偵測到Digilent target、
  `arm_dap_0`與`xc7z020_1`；因尚無production top/v4 bitstream，未program PL。
- 2026-09-05：完成九個Sequential v4＋運算端sparsity checkpoints，最終commit
  `67b5157`建立`sequential_v4_pe_memory_subsystem`。真實v4 image與frozen PE的
  connected XSim為2,551,777 checks PASS，真實global FSM雙frame harness為
  2,385,005 checks PASS；routed OOC在100 MHz達WNS +0.242 ns，使用19,546 LUT、
  23,601 FF、68 RAMB36E1、2 RAMB18E1與37 DSP48E1。此結果包含完整stage DDR load
  與compute-side sparsity，但不包含mailbox、DeepFilter、完整top/BD或板測。
- 2026-09-05：在`docs/memory/`建立Sequential v4 accelerator-top handoff、
  source/compile allowlist與SHA256SUMS；將已放棄的parameter-memory ping-pong研究線
  集中歸檔。原本未提交的
  `active_index_list_store` Phase B檔案以byte-identical checksum保存，但不被提升為
  production或已批准checkpoint。v3檔案因仍是v4 generator/test與歷史板級artifact
  的實際相依而保留。
- 2026-09-03：完成parameter BRAM可追溯hardware artifact generation。Windows
  Vivado 2018.3從乾淨temp重建PYNQ-Z1 BD，route/sign-off無退步後執行
  `write_bitstream`，產生同basename BIT/HWH/LTX並保存commit/tool/part/clock/timing與
  SHA-256 manifest。Python 20/20通過且Stage-2-only mock明確不會進Stage 1。因prompt、
  repository與environment皆無具名PYNQ-Z1 endpoint，未掃描／猜測地址，未program PL或
  執行driver；combined checkpoint為BLOCKED，Stage 1不允許開始。
- 2026-09-03：完成global FSM與formal `pe_array_datapath`的job-lifecycle contract。
  `fb_start/sb_start/df_start`改為held ready/valid；operator done會被保存到完整PE
  barrier，`pe_fault`對應error code 8並產生`pe_abort_pulse`。更新後Windows XSim
  25/25 PASS；FSM-only XC7Z020 100 MHz OOC為159 LUT、79 FF、0 DSP/BRAM、
  WNS +4.750 ns。Memory payload與PE micro-schedule controller仍待整合。
- 本次審查的程式／RTL基準：`codex/memory-design-guidelines` @
  `3457166 Add verified PE spike decision checkpoint`。此commit實際只含50-line RTL，
  尚未加入matching verification/report或formal baseline archive，因此本頁仍列候選。
- 最新PE baseline promotions：gate postprocess `12760c8`、membrane sequencer
  `917bb00`、output serializer `ac02a58`、shared requant engine `8f49e53`。
- 前一個 GSN cell checkpoint branch：`codex/gsn-cell`
- 前一個 PE Array checkpoint branch：`codex/pe-array-small-model`
- 前一個 global FSM checkpoint branch：`codex/global-fsm-subband-schedule`
- Global FSM checkpoint commit：`778ceef Add verified global FSM and subband schedules`
- Initial baseline：`124a771 Establish verified Zephyr FPGA project baseline`
- Feasibility gate commit：`7b9e51f Require PYNQ-Z1 feasibility review for module work`
- `upstream/` 已以 gitlink 記錄 commit
  `13ea1405c9a400aac647025a42b216975765a9bb`。其21個dirty files經
  `git diff --ignore-space-at-eol`核對為EOL-only差異；仍不得由外層審查commit納入、
  reset或格式化。
- 外層目前尚未設定 shared remote，也尚未 push；本機已有可供 `git log`、diff
  與後續分支工作的版本歷史，但其他電腦要取得它仍需完成 remote 發布。

## 2026-09-02 全資料夾審查快照

| 項目 | 審查結果 | 證據界線／處置 |
| --- | --- | --- |
| Repository inventory | 外層Git有493個tracked entries；可見的非`upstream`檔案474個。主要RTL source tree有44個`.v/.sv`候選（含experimental與1個non-baseline候選），但formal PE baseline只有8個模組 | 檔案存在或commit名稱含`verified`不等於formal completion；以baseline manifest與matching evidence為準 |
| Fresh host checks | `python3 -m pytest -q rtl/tests`為12/12 PASS；`reference_checks.py`為13/13 PASS；PE baseline `sha256sum -c`為111/111 OK；本頁82個local links全存在 | 這是2026-09-02本機重跑的host/checksum/link證據，不是HDL simulation或硬體結果 |
| Saved HDL evidence | full XSim log為22/22、memory-only XSim為3/3、先前Icarus為24/24；8個formal PE modules皆保存self-checking XSim、適用的reference與positive-WNS OOC報告 | 本機shell沒有Icarus/Vivado，故本次未重跑HDL或synthesis，只核對已commit log/report與checksum |
| PYNQ-Z1 analytical fit snapshot | 以8-module PE intended count + memory v1 + mailbox + FSM相加約15,981 LUT（30.0%）、15,561 FF（14.6%）、37 DSP（16.8%）、66 RAMB36（47.1%） | 只是跨不同OOC top/clock的分析相加；未含active-index path、controller/top、state/FIFO、AXI IP、DMA、CDC、DeepFilter與routing margin，不能宣稱full-system fit |
| Tracked non-baseline candidate | `pe_spike_decision.v`為50-line Verilog-2001候選，語意上是既有experimental `.sv`的QBN-only整理版；commit `3457166`只有RTL | 不納入formal進度；需matching contract、TB/reference、OOC與baseline approval |
| Upstream state | gitlink仍指向`13ea140`；21個modified files為EOL-only差異；upstream remote存在，outer remote不存在 | 不把dirty marker誤認成模型內容變更，也不在本次清理 |
| Documentation consistency | PE manifest/handoff說8個formal modules；PE subtree `AGENTS.md`/module plan仍說4個且把後四個列為planned | 在下一個formal PE checkpoint前必須修正；本頁採Git較新的manifest/handoff描述，但明列衝突 |
| Estimate freshness | `estimate_zephyr_fpga.py`仍把1個PL LayerNorm lane與1,852 cycles/frame算入39,761-cycle結果；`ZEPHYR_FPGA_ESTIMATE.md`已註明此假設被PS/mailbox分工取代 | 目前RTF只可視為legacy analytical scenario；待PS LayerNorm、mailbox與完整schedule量測後重建，不可當成現行實測 |

## 新成員先掌握的系統邊界

目前已確認的分工是：STFT、ISTFT 與 fullband LayerNorm 暫時留在外部 PC/host；
subband frequency unfold、feature concatenation、subband LayerNorm 及 INT8
packing 放在 PYNQ-Z1 PS CPU；PL RTL 接收已正規化的 INT8 feature。權重、
activation 與 recurrent state 以 INT8 表示，MAC/bias accumulator 使用 INT32。

```text
PC / host                         PYNQ-Z1 PS                 PYNQ-Z1 PL
STFT + magnitude
fullband LayerNorm + INT8 pack ---------------------------> fullband GSU1
                                                            -> GSU2
                                                            -> projection
                                  <--- 64-element FB result ---|
                                  frequency unfold + concat
                                  subband LN(46/94/158)
                                  INT8 pack (782 B/frame) ----> subband GSU/projection
                                                               -> DeepFilter
ISTFT <---------------------------------------------------- enhanced bins
```

這個切分會造成每frame一次PL->PS->PL dependency；此LayerNorm往返的production
baseline為GP-mapped dual-port BRAM mailbox，不經DDR controller或AXI DMA。PS software
的device/uncached MMIO、ordering barrier、雙slot ownership、interrupt/polling與實際
latency都是正式驗收項目，不能只用payload bandwidth推定效能。詳細決策見
[PYNQ PS subband preprocessing](team_workspace/decisions/2026-09-01-pynq-ps-subband-preprocessing.md)。

Memory transport固定為三條互斥ownership：PL消費的靜態weights/bias/requant與
global LUT由v4 image經PS DDR、`memory.v` custom AXI AR/R載入單一parameter stage
cache；
PS LayerNorm intermediate經4 KiB mailbox BRAM與`M_AXI_GP`直接MMIO；external
fullband ingress/final egress才經Xilinx AXI DMA與64-bit AXI4-Stream。PS使用的
LayerNorm float parameters不進PL cache。完整ownership、mailbox、packet、reset/
CDC/error與12個驗收gate見
[Memory設計準則](docs/memory/MEMORY_DESIGN_GUIDELINES.md)。

目前production hierarchy為
`accelerator_system_top -> accelerator_control_axil + accelerator_top -> fsm.v +
sequential_v4_sparse_memory_subsystem + layernorm_mailbox +
feature/coefficient/DeepFilter/final-stream glue`；外層PYNQ-Z1 BD再連接PS7、兩個DMA、
AXI interconnect、AXI BRAM Controller、reset與interrupt。Global FSM、sparse stage
loader/planner、stage-release/full-PE barrier、PE micro-schedule、跨frame recurrent
state/list、mailbox-to-FSM atomic adapter、dense-feature dispatcher、coefficient store、
DeepFilter與final result stream已完成connected RTL。Consumer-native weight order為
`{source_index,row_tile,lane}`；sparse load以context union減少eligible weight DDR bytes，
mandatory matrices/parameters仍完整載入，且ping-pong overlap仍不屬目前baseline。

### FPGA權重寫入與重排建議

- 保留`upstream/parameters/parameters.bin`作為不可修改的row-major source of truth；
  不直接覆寫原始模型權重。
- 首選在PC/host離線執行v4 generator，產生FPGA-ready
  `parameters_v4.bin`、layout JSON、Verilog offset/header及逐值golden結果。PYNQ PS
  只需把已排列好的image放入DDR，再透過AXI/memory loader寫入PL cache。
- Weight physical order固定為
  `{operator,matrix,source_index,row_tile,lane}`；每個row tile是16個INT8 weights／
  128 bits，既有64-bit loader以兩個相鄰beats組成一個PE word。
- 開發階段可由PYNQ PS在啟動時repack到另一個DDR buffer，但會增加CPU時間、DDR
  空間與software複雜度；不建議在PL接收row-major資料後再transpose，因為會增加
  random-write控制、buffer及BRAM壓力。
- 重新排列只解決16-lane strided gather。若每次仍完整預載stage，DDR傳輸量不變；
  要利用spike sparsity減少DDR bytes，memory service還必須先取得active indices，再
  按需burst對應source rows，或使用較小的active-source/tile ping-pong cache。

## 目前功能狀態

| 區塊 | 狀態 | 已有結果 | 尚缺項目 |
| --- | --- | --- | --- |
| 基礎算術與資料路徑 leaf modules | 已完成行為測試 | 13 個獨立 RTL leaf；包含 requantization、saturation、PE、sigmoid、GSU state、serializer、weight buffer 與 complex MAC | synthesis 與板測 |
| Sparsity-aware matvec | CP7 registered-write sparse load＋運算端路徑及板端profile已驗證 | 16個eligible matrix roles依context union scatter載入；dense/sparse connected XSim為12,450,566 checks PASS。`fileid_081` 4,246-frame PL profile為77.115% request/MAC skip、55.179% parameter-byte savings且cycle conservation PASS | 單一代表檔不可外推所有資料；尚無physical DDR rail power，RTF仍大於1 |
| 單一 GSU layer | 已完成 reduced-dimension 行為測試 | shared-weight gate、persistent state、sparse recurrent reads、clear 與 backpressure 通過 | 320-neuron full-size + 真實權重/trace |
| Fullband layer 1 -> layer 2 -> projection | Sequential v4 full-shape datapath已完成production top與板端音訊 | 真實v4 weights/parameters、64->320->320->64、persistent state/list、sparsity、DeepFilter與result egress connected；matrix frozen-oracle exact，100檔426,196 frames皆PASS | 尚未達real-time；不支持其他資料集／板卡泛化 |
| PYNQ PS subband preprocessing | Mailbox、FSM adapter、GP0與native LayerNorm已上板 | 64-byte output／782-byte input ownership、ARM barrier、bulk MMIO與native LayerNorm通過matrix及100檔；最佳非busy設定mean mailbox 1.491 ms | IRQ取代polling未量測；PESQ/STOI套件仍缺 |
| AXI boundary wiring | Full production BD、artifact、JTAG與PYNQ DMA traffic完成 | GP0 control/mailbox、HP0參數、HP1 fullband MM2S、HP2 result S2MM、HP3 spectrum MM2S與64-bit AXIS皆實際跑過150,040-frame matrix及426,196-frame音訊；DMA error為0 | 不代表persistent flash、physical power或其他overlay |
| Control／interrupt／reset | RTL、BD、host helper與實板reset gate完成 | Atomic START、held mailbox命令、IRQ W1C、first-fault、persistent reset quiesce、registered safe proof與epoch；matrix 49次及100檔100次pre-run reset皆epoch +1且三DMA停止／0 error | 尚無fault-injected後的recovery inference、reprogram與power-cycle recovery結論；endurance未完成 |
| Version history / PYNQ feasibility gate | 已完成 | 外層 baseline commit、submodule pointer、generated-file ignore、安全去識別化、強制 Gate A/B/C checklist | shared remote、push、team clone/PR 驗證 |
| PYNQ module audit / real sparse reads | audit checkpoint 已完成 | 23 modules逐一分級；blob 2,193,288 B、220 tensor hashes verified；16個runtime-eligible matrix在約6.25% active時logical reads為3,394/54,304；v3 artifacts現已逐值驗證 | 修正其他blocked架構、完整connected PE/memory intended-count、implementation/board evidence |
| Memory stage cache 與 tensor mapping | Sequential v4 production image已接full BD HP0並上板 | deterministic 1,053,056-byte v4 image；最大stage 219,360 B；單一256 KiB cache、2,040-byte LUT、12-stage geometry/golden；matrix與100檔均以pinned image/parameter hashes完成，DMA／fault為0 | 尚缺外部功率與更直接的HP0 bandwidth分解；舊v3 board artifact不相容 |
| Formal PE Array baseline v1 | 11個frozen leaves + 1個integration wrapper；已接Sequential v4 subsystem | Frozen hierarchy與bit-exact tests保留；PE＋memory subsystem兩frameXSim、routed OOC、full-BD route及BIT/JTAG programming已保存 | CDF ports在subsystem內固定inactive；尚缺DMA traffic與end-to-end板測 |
| 單一 GSN/GSU neuron cell | bit-exact standalone reference core | 兩個fullband cell各320個真實channel + 各16個stress，672/672 XSim PASS；reset/abort、96筆backpressure、tag與clipping皆自動檢查；100 cycles；1,172 LUT/1,484 FF/5 DSP/1 BRAM18、5 ns WNS +0.263 ns | 不屬Sequential v4 production allowlist且不得複製320份；其資源／latency不能代替connected subsystem或top evidence |
| Global `fsm.v` / sparse subsystem / production tops | ec457b1 RTL/top、full implementation、artifact與PYNQ runtime完成 | Frame-sampled sparse mode、fatal handling、hardware-acknowledged reset；XSim、full route、matrix frozen oracle及100檔audio/fault gates PASS | Endurance與fault-injected recovery inference尚未完成；RTF仍大於1 |
| PL subband / DeepFilter | Subband GSU/projection、DeepFilter及DMA AXIS已完成板端音訊 | 九context coefficient store、五幀history、5/3/1-tap complex MAC；spectrum MM2S/result S2MM實際完成100檔426,196 frames，SNR/SI-SDR平均改善 | PESQ/STOI未取得；品質結果只適用pinned corpus/image |
| FPGA implementation | ec457b1 100 MHz release gate、BIT/HWH與板端runtime PASS | Vivado 2018.3 standard WNS +0.264 ns、250 ps guardband WNS +0.014 ns、guardbanded WHS +0.006 ns、raw hold +0.056 ns，0 routing/blocking-DRC error；27,761 LUT/38,456 FF/77.5 BRAM36 equivalent/46 DSP，均低於80% | Vivado vectorless 1.589 W不是physical power；runtime RTF不等於implementation timing |

## 最新驗證證據

| 證據類型 | 最新結果 | 可支持的結論 | 不能支持的結論 |
| --- | --- | --- | --- |
| PYNQ-Z1 ec457b1 runtime／100-audio（2026-09-08） | 9次correctness/profile＋40次benchmark共150,040 frames PASS；100檔共426,196 frames／3,408.768 s evaluated audio，100/100 PASS。100次pre-run reset皆epoch +1且DMA停止／0 error；最終fault/control/DMA error皆0。Weighted mean frame 11.055 ms，aggregate frame/board-loop/E2E RTF 1.382/2.739/2.853；SNR平均改善+7.688 dB。代表性PL profile為77.115% MAC skip、55.179% parameter-byte savings | 可支持ec457b1 image、PYNQ 3.0.1、指定100-triplet corpus下的correctness、latency、RTF、sparsity、traffic及SNR/SI-SDR板端結果；可支持hardware-acknowledged reset與DMA cleanup在這些run通過 | RTF仍大於1，不能宣稱real time；PESQ/STOI未取得；179,000-frame endurance只屬partial checkpoint；Vivado 1.589 W不是physical board power；不支持persistent flash或其他板卡／資料集泛化 |
| Full accelerator artifact／PYNQ-Z1 JTAG（2026-09-07） | Baseline `eb496dd2`的route checkpoint重算release gates後產生matching BIT/HWH；BIT SHA `33afbe9c…a1a420`。具名target `003017B78476A` program PASS，DONE=1且configuration errors=0；AHB-AP0唯讀ABI及AXI-Lite reachability PASS | 指定BIT已載入唯一`xc7z020_1`，configuration健康，control identity為`0x00040001`且packet sizes正確 | 這是volatile PL configuration，不是QSPI flash；DMA Idle未assert，沒有reset/traffic、PYNQ runtime、DDR/coherency、golden、RTF、功耗或音訊品質證據 |
| Full Zynq BD implementation（2026-09-07） | Clean baseline `eb496dd2`重建control XSim、BD、global synthesis及完整implementation；standard WNS +0.301 ns、250 ps guardband WNS +0.051 ns、guardbanded WHS +0.012 ns、raw hold +0.062 ns、TNS/THS 0；25,194 LUT、34,812 FF、77.5 BRAM36 equivalent、46 DSP；0 routing errors、CDC safely timed、0 blocking DRC | 含PS7、GP0、HP0..HP3、兩個DMA、mailbox、IRQ、DMA-safe reset separation與production accelerator的完整BD通過100 MHz setup/hold、coverage、CDC、DRC及<80%資源gate | Implementation本身不支持board DMA/MMIO/coherency、end-to-end golden、RTF、功耗、音訊品質或實板功能結論 |
| Full Zynq BD pre-implementation（2026-09-06） | Control XSim 1,695 ns PASS；PYNQ-Z1 BD validation PASS；Vivado 2018.3 global synthesis完成且0 errors／0 critical warnings；WNS -0.321 ns、WHS +0.045 ns；31,016 LUT、35,326 FF、77.5 BRAM36 equivalent、46 DSP；CDC safely timed且0 unconstrained internal endpoints | PS7 GP0、HP0..HP3、兩個DMA、mailbox、IRQ與split reset的結構可validate／synthesize；資源pre-implementation gate低於80%；control register handshake/error行為已驗證 | Setup尚未達100 MHz；未執行opt/place/phys-opt/route，沒有bitstream、PS driver、DDR/DMA end-to-end、RTF、功耗或板測 |
| Sparse accelerator top（2026-09-06） | `tb_fsm` sparse-mode/error contract、既有mailbox/dispatcher/coefficient-store/DeepFilter及focused timing-cut 7/7 PASS；完整top elaboration PASS；routed OOC WNS +0.115 ns／WHS +0.016 ns、24,461 LUT、28,443 FF、71 RAMB36、4 RAMB18、46 DSP，0 failed/unrouted nets | FSM與CP6 sparse ABI相容、production allowlist可綜合且single-clock top 100 MHz setup/hold通過，資源類別低於80% | 不支持PS7/AXI/DMA/CDC full implementation、bitstream、板上DDR traffic、RTF、功耗或音訊品質 |
| Accelerator top Step 4（2026-09-05） | Adapter＋mailbox XSim PASS；完整`accelerator_top` elaboration PASS；Vivado 2018.3 OOC synthesis 0 errors，WNS -2.863 ns、21,050 LUT、24,109 FF、69 RAMB36、3 RAMB18、37 DSP；0 no-clock與0 unconstrained internal max-delay pins | FSM、frozen subsystem、mailbox與782-byte atomic buffer可在同一synthesizable hierarchy編譯；64-byte publish、完整PS return、release、frame ID及read backpressure已驗證 | timing gate仍FAIL；沒有full implementation、I/O delay、PS7/AXI/DMA、DeepFilter、bitstream或板測，不能宣稱100 MHz或完整推論功能 |
| Sequential v4 production FSM／JTAG（2026-09-05） | `tb_fsm` PASS（10,036 ns）；真實v4＋frozen PE/memory harness 2,385,005 checks、24 stages、6 FB、54 SB、101,446 sparse PASS；FSM OOC 163 LUT/80 FF/WNS +4.135 ns；JTAG見`arm_dap_0`與`xc7z020_1` | controller排程、reset-only error、held-start one-shot、IDLE fault blocking、兩frame connected行為與板子JTAG identity已驗證 | 未program PL；不支持v4 top、mailbox/DeepFilter/AXI/DMA、板上DDR/MMIO、RTF、功耗或音訊品質 |
| Sequential v4 PE＋memory connected/routed OOC（2026-09-05） | Commit `67b5157`；direct connected XSim 2,551,777 checks PASS，真實global FSM兩frame 2,385,005 checks PASS；Python 140 tests／735 subtests；XC7Z020 routed OOC 100 MHz WNS +0.242 ns、19,546 LUT、23,601 FF、68 RAMB36E1+2 RAMB18E1、37 DSP48E1、0 routing errors | 真實v4 image、12 stages、shared-engine 4/3/2 contexts、persistent state/list、16個sparse roles、一次性global LUT、barrier/release及subsystem internal timing/resource已驗證 | 不支持mailbox/DeepFilter/top/AXI IP/CDC、板上DDR bandwidth、RTF、功耗或音訊品質；每stage DDR仍完整搬移 |
| Parameter BRAM artifact／Stage 2 board checkpoint（2026-09-03） | frozen `78c86f3` hardware inputs在fresh Windows Vivado 2018.3 build重新validate/synth/route後，產生matching BIT/HWH/LTX與SHA manifest；WNS +0.964 ns、WHS +0.019 ns、blocking DRC/unrouted 0；Python 20/20。因無明確PYNQ-Z1 endpoint，program前BLOCKED | 可交付overlay artifacts可追溯至commit/tool/part/clock且HWH同project；Stage-2-only host/mock流程不會進Stage 1 | 沒有board環境、overlay download、HW ID/ABI、contiguous DDR、HP0 counter、5筆readback、release或cleanup證據；不得進Stage 1 |
| Parameter BRAM full-BD implementation（2026-09-02） | Windows Vivado 2018.3 clean BD validate/synth/opt/place/route PASS；WNS +0.964 ns、WHS +0.019 ns、setup/hold failing endpoints 0、unrouted 0；3,814 LUT/5,218 FF/73 RAMB36+1 RAMB18/1 DSP；Python 18/18與real-v3 13/13、`tb_memory`、`tb_memory_service` XSim PASS | GP0/HP0/reset/ILA與64-RAMB36 cache完整BD可在100 MHz route且低於80%資源線；DQS值可追溯至installed preset並在PS7 schema範圍內；Gate PASS WITH RISKS，可進下一個明確授權的bitstream checkpoint | 沒有`.bit/.hwh` deliverable、ARM barrier、MMIO/HP0 coherency、DDR electrical、ILA capture或板測；本機缺Icarus故該regression未重跑 |
| 2026-09-02 repository audit rerun | `pytest rtl/tests` 12/12 PASS；dependency-free reference 13/13 PASS；PE baseline SHA 111/111 OK；本頁local links 82/82存在 | host-side arithmetic、v2/v3 image、sparse-read regressions與archive完整性在目前working tree重跑一致 | 本次沒有Icarus/Vivado；不支持新HDL compile/XSim/OOC、implementation或板測 |
| Windows Vivado 2018.3 full XSim（2026-09-03） | 25/25 PASS，含更新後`tb_fsm` | FSM確認12-stage、27個subband jobs、held start backpressure、done後延遲PE barrier、PE fault/abort、共享/三路schedule、reset/timeout及錯誤注入；其餘既有TB無回歸 | 三路控制不代表三套PE/memory fit；尚非formal PE datapath + production Memory的connected test，也不代表AXI IP、RTF或板測 |
| Memory v1 Python / Icarus / XSim | Python 12/12於2026-09-02重跑；Icarus全RTL 24/24與memory-only Vivado XSim 3/3為保存的先前PASS | v3逐weight/parameter/LUT與determinism；loader/service/mailbox的backpressure、bounds、abort/timeout、stale/duplicate/partial/padding/reset路徑 | 本次未重跑HDL；不代表FSM/top/full-size integration、PS driver、MMIO latency或板測 |
| Memory v1 Vivado OOC | `memory_service` 5,999 LUT/6,580 FF/1 DSP/64 RAMB36/WNS +1.858 ns；mailbox 1,120 LUT/801 FF/1 RAMB36/WNS +1.647 ns | XC7Z020 100 MHz standalone internal timing與true-BRAM inference通過；0 unconstrained internal max-delay pins | OOC I/O尚無delay/`HD.CLK_SRC`；未含AXI BRAM Controller/interconnect、PE、place/route或完整fit |
| Python integer reference | 13/13 PASS（2026-09-02重跑） | testbench使用的arithmetic、sparse profiles與reduced fullband sequence reference一致 | 不代表HDL編譯或硬體結果 |
| Python memory image integrity | 2/2 PASS；generator temp regeneration 與 binary/JSON/header snapshot 三者 `cmp` PASS | current `upstream/parameters` 的 shared-gate compact v2 image 可重建且 snapshot 同版 | 不代表 v2 row-major image 能正確驅動 16-lane GSU/fullband |
| 附件既有 Memory XSim 紀錄 | source handoff 記載 Vivado 2024.1 memory TB PASS；bundle 未附 console log | 可保留先前本機工作的 provenance | 不能當成目前 classified paths、Vivado 2018.3 或整合後 regression 的新證據 |
| Vivado synthesis / implementation | 8個formal PE modules（200 MHz）及GSN cell、FSM、mailbox仍為positive-WNS standalone OOC；parameter GP0/HP0/ILA BD另有完整100 MHz post-route證據 | 指定OOC module的internal timing，以及parameter bring-up完整BD的resource/clock/DRC/route已量測 | 不代表完整PE跨clock integration、三路subband、bitstream或板測 |
| PYNQ-Z1 board | 2026-09-07具名Digilent target `003017B78476A`已program full accelerator BIT；internal/pin/IR DONE=1，CRC/IDCODE/security error=0；read-only ABI PASS，三DMA status均`0x1` | 可確認BIT實際載入指定FPGA、configuration健康及AXI-Lite control register可讀且ABI正確 | DMA未達Halted+Idle契約，未執行reset/traffic；不可宣稱DDR/coherency、latency、RTF、功耗、音訊品質或persistent flash |
| `pe_requant_lane` reference/XSim/OOC | standalone reference 5,155 vectors verified；XSim 5,155/5,155 PASS；OOC WNS +0.263 ns | signed INT32 x signed multiplier、sign-symmetric rounding、shift 0..62、tag/backpressure bit-exact；latency 9、II=1；單 lane 達 200 MHz | 不支持 4-lane bank、完整 workload/RTF、place-and-route 或板上結果 |
| `pe_local_requant_bank_4lane` reference/XSim/OOC | standalone reference 2,112 packets/4,149 active results verified；XSim PASS；OOC WNS +0.263 ns | 四lane mixed mask/parameter/tag/backpressure bit-exact；latency 9、bank II=1、最多4 results/cycle；2,167 LUT、1,732 FF、16 DSP | 不支持完整PE Array route、parameter-memory bandwidth、frame RTF或板上結果 |
| Formal PE baseline v1 archive | 8 modules；SHA256SUMS 111/111 OK；各module保存self-checking XSim與5 ns OOC，reference在適用處保存。新增四個checkpoint為gate 1,520 packets/5,007 results、membrane 96 tiles/663 results、serializer 519 tiles/4,014 outputs、shared RQ 3,500 vectors | 每個accepted leaf/control block的固定contract、latency/II、資源與200 MHz OOC timing可追溯 | PE subtree規則/spec仍只列4 modules；不支持完整connected PE、memory/AXI、CDC或board fit |
| Full-shape PE small model XSim | 真實parameters.bin、10,651 commands、85 tile checks PASS | LayerNorm-reference -> 64x320 GSU1 -> 320x320 GSU2 -> 320x64 projection -> DF orders 5/3/1；本frame active為181/169 | GSU phase間postprocess由Python reference銜接；不代表multi-frame、production memory或RTF |
| 16-MAC PE shell OOC | 1,346 LUT、1,050 FF、16 DSP、0 BRAM；5 ns WNS +0.270 ns | 一個16-lane Hybrid MAC array與controller在XC7Z020 post-synthesis達200 MHz | 排除Local RQ/cache/AXI/memory；不代表完整accelerator implementation或板級fit |
| Single GSN cell reference/XSim/OOC | 真實參數672 vectors；XSim 672/672 PASS、latency 100、96 stalled results、63 clipped vectors；OOC 1,172 LUT/1,484 FF/5 DSP/1 BRAM18、5 ns WNS +0.263 ns | 單一神經元的7次requant、sigmoid、膜電位、folded BN、state/spike與協定bit-exact，且standalone cell達200 MHz post-synthesis | 不支持複製320 cells；不包含matrix MAC、weight fetch、完整layer scheduler、place-and-route或板測 |
| Real parameter sparse-read host test | 5/5 unittest PASS；與memory image test合跑pytest 7/7 PASS；report deterministic regeneration PASS | 2,193,288-byte blob與220個tensor SHA/offset/dtype完整；20 matrix × 5 patterns selected-packed INT32結果等於dense reference；raw row-major不是連續16-lane word | 不支持RTL address adapter、DDR transaction減少、cycles、timing、RTF或板上加速 |

- Full-design implementation摘要：[rtl/reports/accelerator_full_bd_implementation/summary.md](rtl/reports/accelerator_full_bd_implementation/summary.md)
- Full accelerator artifact摘要：[rtl/reports/accelerator_full_artifacts/summary.md](rtl/reports/accelerator_full_artifacts/summary.md)
- First-board programming摘要：[rtl/reports/accelerator_full_board/summary.md](rtl/reports/accelerator_full_board/summary.md)
- 夜間執行報告：[docs/OVERNIGHT_HARDWARE_EXECUTION_REPORT.md](docs/OVERNIGHT_HARDWARE_EXECUTION_REPORT.md)
- PYNQ-Z1 first-board runbook：[docs/PYNQ_Z1_ACCELERATOR_BOARD_RUNBOOK.md](docs/PYNQ_Z1_ACCELERATOR_BOARD_RUNBOOK.md)
- Reset/DMA recovery契約：[docs/HARDWARE_RESET_AND_DMA_RECOVERY.md](docs/HARDWARE_RESET_AND_DMA_RECOVERY.md)
- ec457b1 board evidence：[rtl/reports/accelerator_optimization_final/board_runs/ec457b1/README.md](rtl/reports/accelerator_optimization_final/board_runs/ec457b1/README.md)
- Implementation warning triage：[docs/HARDWARE_IMPLEMENTATION_WARNING_TRIAGE.md](docs/HARDWARE_IMPLEMENTATION_WARNING_TRIAGE.md)
- Hold-margin handoff：[team_workspace/handoffs/2026-09-07-full-design-hold-margin.md](team_workspace/handoffs/2026-09-07-full-design-hold-margin.md)
- Full-design implementation handoff：[team_workspace/handoffs/2026-09-07-full-design-implementation.md](team_workspace/handoffs/2026-09-07-full-design-implementation.md)
- Full-design pre-implementation摘要：[rtl/reports/accelerator_full_bd_preimplementation/summary.md](rtl/reports/accelerator_full_bd_preimplementation/summary.md)
- Full-design pre-implementation handoff：[team_workspace/handoffs/2026-09-06-full-design-preimplementation.md](team_workspace/handoffs/2026-09-06-full-design-preimplementation.md)
- Sequential v4 accelerator-top handoff：[docs/memory/HANDOFF.md](docs/memory/HANDOFF.md)
- Sequential v4 source/compile manifest：[docs/memory/MANIFEST.md](docs/memory/MANIFEST.md)
- Sequential v4 source checksums：[docs/memory/SHA256SUMS](docs/memory/SHA256SUMS)
- Sequential v4 normative contract：[docs/memory/SEQUENTIAL_V4_PE_MEMORY_CONTRACT.md](docs/memory/SEQUENTIAL_V4_PE_MEMORY_CONTRACT.md)
- Sequential v4 connected/routed evidence：[rtl/reports/sequential_v4_pe_memory_subsystem/summary.md](rtl/reports/sequential_v4_pe_memory_subsystem/summary.md)
- Archived parameter-memory ping-pong research：[archive/parameter_memory_ping_pong/README.md](archive/parameter_memory_ping_pong/README.md)
- XSim 總結：[rtl/test-results/xsim-console.log](rtl/test-results/xsim-console.log)
- FSM XSim 結果：[rtl/test-results/tb_fsm-xsim.log](rtl/test-results/tb_fsm-xsim.log)
- FSM 架構與state定義：[docs/GLOBAL_FSM_AND_SUBBAND_SCHEDULE.md](docs/GLOBAL_FSM_AND_SUBBAND_SCHEDULE.md)
- FSM OOC metrics：[rtl/reports/fsm/metrics_post_synth.txt](rtl/reports/fsm/metrics_post_synth.txt)
- Python reference：[rtl/tests/reference_checks.py](rtl/tests/reference_checks.py)
- Memory image test：[rtl/tests/test_axi_memory_image.py](rtl/tests/test_axi_memory_image.py)
- Memory設計準則：[docs/memory/MEMORY_DESIGN_GUIDELINES.md](docs/memory/MEMORY_DESIGN_GUIDELINES.md)
- Memory v1設計／Gate A／OOC報告：[docs/memory/MEMORY_V1_FEASIBILITY.md](docs/memory/MEMORY_V1_FEASIBILITY.md)
- Memory v1 Vivado摘要：[rtl/reports/memory_v1/summary.md](rtl/reports/memory_v1/summary.md)
- Memory v3逐值測試：[rtl/tests/test_memory_v3_image.py](rtl/tests/test_memory_v3_image.py)
- Parameter BRAM bring-up計畫：[docs/memory/PARAMETER_BRAM_BOARD_BRINGUP_PLAN.md](docs/memory/PARAMETER_BRAM_BOARD_BRINGUP_PLAN.md)
- Parameter BRAM pre-bitstream證據：[rtl/reports/parameter_bram_bringup/summary.md](rtl/reports/parameter_bram_bringup/summary.md)
- Parameter BRAM full-BD post-route證據：[rtl/reports/parameter_bram_implementation/summary.md](rtl/reports/parameter_bram_implementation/summary.md)
- Memory integration analysis：[docs/memory/MEMORY_INTEGRATION_ANALYSIS.md](docs/memory/MEMORY_INTEGRATION_ANALYSIS.md)
- PYNQ module audit / sparse reads：[docs/PYNQ_Z1_MODULE_AUDIT_AND_SPARSE_READS.md](docs/PYNQ_Z1_MODULE_AUDIT_AND_SPARSE_READS.md)
- Sparse parameter test：[rtl/tests/test_sparse_parameter_reads.py](rtl/tests/test_sparse_parameter_reads.py)
- Machine-readable report：[outputs/memory/2026-09-01/sparse_parameter_read_report.json](outputs/memory/2026-09-01/sparse_parameter_read_report.json)
- Formal PE baseline manifest：[rtl/pe_array/baseline/v1/MANIFEST.md](rtl/pe_array/baseline/v1/MANIFEST.md)
- Formal PE baseline checksums：[rtl/pe_array/baseline/v1/SHA256SUMS](rtl/pe_array/baseline/v1/SHA256SUMS)
- 最新PE handoff：[rtl/pe_array/HANDOFF.md](rtl/pe_array/HANDOFF.md)
- 尚待同步的PE module plan：[rtl/pe_array/spec/MODULE_DEVELOPMENT_PLAN.md](rtl/pe_array/spec/MODULE_DEVELOPMENT_PLAN.md)
- PE operator/full-shape summary：[rtl/pe_array/reports/pe_small_model/summary.md](rtl/pe_array/reports/pe_small_model/summary.md)
- 16-MAC OOC metrics：[rtl/pe_array/reports/pe_array_top/metrics_post_synth.txt](rtl/pe_array/reports/pe_array_top/metrics_post_synth.txt)
- GSN cell 中文架構與結果：[rtl/pe_array/reports/pe_gsn_cell/summary.md](rtl/pe_array/reports/pe_gsn_cell/summary.md)
- GSN cell XSim 摘要：[rtl/pe_array/reports/pe_gsn_cell/xsim_result.txt](rtl/pe_array/reports/pe_gsn_cell/xsim_result.txt)
- GSN cell OOC metrics：[rtl/pe_array/reports/pe_gsn_cell/metrics_post_synth.txt](rtl/pe_array/reports/pe_gsn_cell/metrics_post_synth.txt)
- Legacy analytical estimator：[ZEPHYR_FPGA_ESTIMATE.md](ZEPHYR_FPGA_ESTIMATE.md)
- 全部 testbench：[rtl/tb/](rtl/tb/)

320x320 sparsity regression 的 weight read 次數為：0/16/32/64/96/160/320
個 active spikes 分別讀取 0/320/640/1280/1920/3200/6400 次；dense baseline
固定為 6400 次。這是包含 serial 320-bit scan 與人工 backpressure 的 deterministic
simulation，不是 PYNQ-Z1 latency 數據。

## 已完成 checkpoint 與歷史交接

| 日期 | Checkpoint | Primary record | Evidence / handoff |
| --- | --- | --- | --- |
| 2026-09-05 | Sequential v4 PE＋memory baseline | [normative contract](docs/memory/SEQUENTIAL_V4_PE_MEMORY_CONTRACT.md) | [accelerator-top handoff](docs/memory/HANDOFF.md)／[routed evidence](rtl/reports/sequential_v4_pe_memory_subsystem/summary.md) |
| 2026-08-31 | RTL leaf unit tests | [task](team_workspace/tasks/2026-08-31-rtl-leaf-unit-tests.md) | [handoff](team_workspace/handoffs/2026-08-31-rtl-leaf-unit-tests.md) |
| 2026-08-31 | Sparsity-aware column MAC | [task](team_workspace/tasks/2026-08-31-sparsity-aware-column-mac.md) | [handoff](team_workspace/handoffs/2026-08-31-sparsity-aware-column-mac.md) |
| 2026-08-31 | Realistic synthetic spike regression | [task](team_workspace/tasks/2026-08-31-realistic-spike-regression.md) | [handoff](team_workspace/handoffs/2026-08-31-realistic-spike-regression.md) |
| 2026-09-01 | Single GSU layer | [task](team_workspace/tasks/2026-09-01-single-gsu-layer.md) | [handoff](team_workspace/handoffs/2026-09-01-single-gsu-layer.md) |
| 2026-09-01 | Fullband three-layer path | [task](team_workspace/tasks/2026-09-01-fullband-three-layer-path.md) | [handoff](team_workspace/handoffs/2026-09-01-fullband-three-layer-path.md) |
| 2026-09-01 | 共用專案進度入口 | [task](team_workspace/tasks/2026-09-01-project-status-index.md) | [handoff](team_workspace/handoffs/2026-09-01-project-status-index.md) |
| 2026-09-01 | PYNQ PS subband preprocessing boundary | [task](team_workspace/tasks/2026-09-01-pynq-ps-subband-preprocessing.md) | [handoff](team_workspace/handoffs/2026-09-01-pynq-ps-subband-preprocessing.md) |
| 2026-09-01 | AXI interface wiring tests | [task](team_workspace/tasks/2026-09-01-axi-interface-wiring-tests.md) | [handoff](team_workspace/handoffs/2026-09-01-axi-interface-wiring-tests.md) |
| 2026-09-01 | Memory RTL bundle import and integration analysis | [task](team_workspace/tasks/2026-09-01-memory-rtl-import.md) | [handoff](team_workspace/handoffs/2026-09-01-memory-rtl-import.md) |
| 2026-09-01 | Independent PE Array planning scaffold | [task](team_workspace/tasks/2026-09-01-pe-array-independent-development.md) | [handoff](team_workspace/handoffs/2026-09-01-pe-array-scaffold.md) |
| 2026-09-01 | Independent `pe_requant_lane` | [task](team_workspace/tasks/2026-09-01-pe-array-independent-development.md) | [handoff](team_workspace/handoffs/2026-09-01-pe-requant-lane.md) |
| 2026-09-01 | Independent 4-lane Local Requant Bank | [task](team_workspace/tasks/2026-09-01-pe-array-independent-development.md) | [handoff](team_workspace/handoffs/2026-09-01-pe-local-requant-bank-4lane.md) |
| 2026-09-01 | PE operators and full-shape small model | [task](team_workspace/tasks/2026-09-01-pe-array-small-model.md) | [handoff](team_workspace/handoffs/2026-09-01-pe-array-small-model.md) |
| 2026-09-01 | Version history and PYNQ-Z1 feasibility gate | [task](team_workspace/tasks/2026-09-01-version-history-pynq-feasibility-gate.md) | [handoff](team_workspace/handoffs/2026-09-01-version-history-pynq-feasibility-gate.md) |
| 2026-09-01 | PYNQ module audit and real sparse parameter reads | [task](team_workspace/tasks/2026-09-01-pynq-module-audit-sparse-reads.md) | [handoff](team_workspace/handoffs/2026-09-01-pynq-module-audit-sparse-reads.md) |
| 2026-09-01 | Global FSM and three-subband schedule | [task](team_workspace/tasks/2026-09-01-global-fsm-subband-schedule.md) | [handoff](team_workspace/handoffs/2026-09-01-global-fsm-subband-schedule.md) |
| 2026-09-01 | Single bit-exact GSN/GSU neuron cell | [task](team_workspace/tasks/2026-09-01-gsn-cell.md) | [handoff](team_workspace/handoffs/2026-09-01-gsn-cell.md) |
| 2026-09-01 | Production memory design guidelines | [task](team_workspace/tasks/2026-09-01-memory-design-guidelines.md) | [handoff](team_workspace/handoffs/2026-09-01-memory-design-guidelines.md) |
| 2026-09-02 | Memory v1 correctness baseline | [feasibility](docs/memory/MEMORY_V1_FEASIBILITY.md) | [Vivado summary](rtl/reports/memory_v1/summary.md) |
| 2026-09-02 | Parameter BRAM pre-bitstream bring-up | [bring-up plan](docs/memory/PARAMETER_BRAM_BOARD_BRINGUP_PLAN.md) | [XSim／OOC／BD／dry-run evidence](rtl/reports/parameter_bram_bringup/summary.md)；尚無implementation／bitstream／板測 |
| 2026-09-02 | Parameter BRAM full-BD implementation | [bring-up plan](docs/memory/PARAMETER_BRAM_BOARD_BRINGUP_PLAN.md) | [post-route evidence](rtl/reports/parameter_bram_implementation/summary.md)；Gate PASS WITH RISKS，未產生bitstream／未板測 |
| 2026-09-03 | Parameter BRAM artifacts / Stage 2 board smoke | [bring-up plan](docs/memory/PARAMETER_BRAM_BOARD_BRINGUP_PLAN.md) | [artifact與blocker evidence](rtl/reports/parameter_bram_board_stage2/summary.md)；BIT/HWH/LTX PASS，board connection/program前BLOCKED，未執行Stage 2/1 |
| 2026-09-02 | Formal PE baseline v1擴充至8 modules | [manifest](rtl/pe_array/baseline/v1/MANIFEST.md) | [latest handoff](rtl/pe_array/HANDOFF.md) |

較早 handoff 內的測試總數保留當時 checkpoint 的歷史值；最新整體結果一律以
本頁「最新驗證證據」與最新測試 log 為準。

## 已定案的跨任務決策

- [Sequential v4 PE＋memory baseline](docs/memory/SEQUENTIAL_V4_PE_MEMORY_CONTRACT.md)：
  單一256 KiB stage cache、完整stage DDR load、運算端active-list sparsity、row-tile
  GSU schedule、20組persistent context及reset-only fatal recovery；取代已歸檔的
  parameter-memory ping-pong contract作為目前production authority。
- [Sparse weight column layout](team_workspace/decisions/2026-08-31-sparse-weight-column-layout.md)：
  active spike index 對應 weight column，以 `{column, row_tile}` 讀取 packed lanes。
- [Source-major 16-lane physical layout](team_workspace/decisions/2026-09-01-sparse-column-packed-weight-layout.md)：
  v3 image把原matrix column存成`{source_index,row_tile,lane}`，讓一個active source的
  row tiles連續；完整stage preload本身不會因sparsity減少DDR bytes。
- [GSU shared weight tile interface](team_workspace/decisions/2026-09-01-gsu-shared-weight-tile-interface.md)：
  GSU arithmetic 與外部 weight/parameter storage 解耦，讓 `memory.v` 後續決定
  BRAM/DDR tiling。
- [PYNQ PS subband preprocessing](team_workspace/decisions/2026-09-01-pynq-ps-subband-preprocessing.md)：
  subband unfold、concat、LayerNorm 與 INT8 packing 在 PS software 執行；PL 只接收
  normalized INT8 subband vectors。
- [AXI interface partition](team_workspace/decisions/2026-09-01-axi-interface-partition.md)：
  PS/PL control使用32-bit AXI4-Lite，external fullband ingress/final egress使用64-bit
  AXI4-Stream；早期stream weight/runtime prototype保留為歷史證據，production
  parameter與LayerNorm intermediate transport已由下列decision部分取代。
- [Parameter/runtime transport partition](team_workspace/decisions/2026-09-01-parameter-and-runtime-data-transport-partition.md)：
  PL靜態parameter走`memory.v` custom AXI read ->大型BRAM -> `memory_service`；
  LayerNorm 64/782-byte round trip走GP-mapped 4 KiB mailbox BRAM；external ingress/
  final egress走Xilinx AXI DMA/64-bit AXI4-Stream，三者有分離的buffer ownership。
- [PYNQ-Z1 feasibility gate](team_workspace/decisions/2026-09-01-pynq-z1-feasibility-gate.md)：
  每個 RTL/PS datapath/memory/AXI 模塊在實作前先做 scaled feasibility，完成後
  依風險執行 OOC synthesis；分析、XSim、synthesis、implementation、板測不混用。
- [Global FSM and subband parallelism](team_workspace/decisions/2026-09-01-global-fsm-subband-parallelism.md)：
  預設一個subband PE time-multiplex 4/3/2 contexts；FSM保留三engine/bank平行控制，
  但在完整PE/memory OOC、implementation與板測通過前，`top.v`預設不得啟用。
- [PE Array small-model boundary](team_workspace/decisions/2026-09-01-pe-array-small-model-boundary.md)：
  LayerNorm維持software/reference；一個16-PE array time-multiplex fullband與DF；
  full-shape單frame使用真實參數，但arithmetic-shell OOC不是完整板級fit。
- [GSN cell resource sharing](team_workspace/decisions/2026-09-01-gsn-cell-resource-sharing.md)：
  standalone cell保留作bit-exact驗證核心；production以16 Hybrid PEs與4-lane Local
  RQ bank跨neuron tiles共享，禁止把單cell資源直接複製320份。

## 跨子系統整體 backlog

後續工作以[accelerator-top handoff](docs/memory/HANDOFF.md)
為入口；`MEMORY_DESIGN_GUIDELINES.md`仍約束transport ownership與證據等級，但其中
v3 image及早期未連接PE的描述已由Sequential v4 contract取代。

1. **完成**：accelerator-top／system-top Phase A已固定source、FCLK0 100 MHz、
   GP0／HP0..HP3、AXI4-Lite／DMA address ownership、packet sizes、frame ID、IRQ與
   ready/valid邊界。
2. **完成**：fullband ingress buffer與stage/context-aware feature dispatcher已接入；
   SB資料只接受matching committed mailbox frame。
3. **完成**：FB projection以64-byte packet原子publish；三個SB projection寫入具
   branch/order/lifetime檢查的九context DeepFilter coefficient store。
4. **RTL／BD完成，software待辦**：mailbox已接FSM、AXI BRAM Controller與held
   claim/commit/release control registers；仍需bit-exact PS LayerNorm、uncached MMIO、
   ordering barrier與IRQ/polling driver。
5. **完成RTL驗證**：DeepFilter coefficient/noisy-history、5/3/1-tap complex MAC、
   scheduler及result stream已接入；尚需完整audio/reference與板測。
6. **BD接線完成，端到端待辦**：external fullband與spectrum使用MM2S、final result
   使用S2MM；mailbox與parameter image維持獨立transport。尚需DDR buffer ownership、
   cache maintenance及DMA packet/frame end-to-end驗證。
7. **完成**：`accelerator_top`、`accelerator_system_top`、global FSM、Sequential v4
   subsystem、mailbox、control、DMA、reset與interrupt已形成可validate／synthesize的
   production hierarchy；`parallel_subbands=0`維持唯一production模式。
8. **部分完成**：真實v4 subsystem、FSM、mailbox、dispatcher、coefficient store與
   DeepFilter已有各自connected regressions，control AXI TB亦通過；仍缺包含PS/DMA模型、
   outstanding AXI、fatal reset restart與frame mismatch的full-system multi-frame regression。
9. **待辦**：重做system cycle/RTF estimator，納入實測stage load、PE scheduler、
   PS LayerNorm、mailbox MMIO、DMA與DeepFilter cycles；不得把compute-side sparsity
   直接當成DDR省量或板上加速。
10. **下一個板端gate**：setup與hold修正、matching BIT/HWH、具名JTAG programming及
    read-only ABI已完成。下一步先取得PYNQ runtime／板版號／kernel資訊並使三個DMA
    安全達Halted+Idle，再依reviewed helper完成單次reset；之後依序驗證DDR buffer
    ownership、cache maintenance、單路與多路DMA、mailbox ordering。含PS LayerNorm
    round-trip的end-to-end golden仍須凍結，完成前不得宣稱推論正確、RTF或音訊品質。

## Git 更新規則

- 開始修改前先讀本頁與 `docs/PYNQ_Z1_FEASIBILITY_CHECKLIST.md`，確認目前狀態、
  適用限制與證據等級。
- 一般工作不建立 task card；只有使用者明確要求時才建立。
- 每次完成的更新必須建立 Git commit；只 stage 本次範圍內的檔案。
- 若已有 shared remote，需要分享或交接時再 push commit 或 branch。
- handoff、decision、本頁更新、獨立 branch 與 pull request 均按需使用，不再是
  每個 checkpoint 的固定要求。
- 測試與技術報告仍須忠實區分分析假設、RTL/testbench、Vivado 與實板證據。
- 修改 `upstream/` 時先提交 nested repository，再於外層提交 gitlink 更新。

## 更新紀錄

- 2026-09-07：完成setup熱路徑重構、full release route、artifact與首次具名PYNQ-Z1
  JTAG燒錄。標準setup WNS +0.301 ns、250 ps setup guardband +0.051 ns、50 ps hold
  guardband +0.012 ns、raw hold +0.062 ns，route/CDC/coverage/blocking DRC/resource gate
  皆PASS。Matching BIT/HWH與manifest產生後，BIT以SHA `33afbe9c…a1a420`燒錄至
  `003017B78476A/xc7z020_1`；DONE與read-only image ABI PASS。三DMA未assert Idle，依
  fail-closed契約停止於零寫入snapshot，未執行reset、DMA或START。

- 2026-09-07：完成夜間reset/DMA安全更新與fresh full implementation。Software reset只
  作用於custom data plane；persistent quiesce、registered safe proof、reset epoch、
  driver三DMA Halted+Idle順序及read-only diagnostics已有RTL/XSim/host證據。Full route
  56,285/56,285 nets，standard WNS +0.197 ns、setup guardband -0.053 ns、hold guardband
  0.000 ns、raw hold +0.050 ns，DRC 0/0/115、methodology 0/0/5。Setup margin gate失敗，
  因此未產BIT/HWH、未program、未宣稱board結果。

- 2026-09-07：full implementation新增50 ps hold guardband並從乾淨allowlist重建。
  最終100 MHz setup WNS +0.160 ns、guardbanded WHS +0.007 ns、raw physical hold
  margin +0.057 ns、TNS／THS與failing endpoints皆0；55,958個routable nets全數完成，
  0 routing errors、CDC safely timed、0 blocking DRC。相較先前raw WHS +0.014 ns改善
  43 ps，且未加入false/multicycle exception；資源只增加37 LUT。未產生BIT/HWH、
  未連板，setup/congestion、soft reset、driver與端到端驗證仍是後續項目。

- 2026-09-07：完成production accelerator的full PYNQ-Z1 implementation。固定
  baseline從乾淨Windows-local staging重跑control XSim、BD validation、global synthesis、
  opt/place/phys-opt/route與routed-design phys-opt；最終100 MHz WNS +0.004 ns、WHS
  +0.014 ns、0 failing endpoints、0 routing errors、CDC safely timed、0 blocking DRC，
  且LUT/FF/BRAM/DSP均低於80%。第一次route的-0.058 ns由post-route phys-opt閉合；
  因setup margin極薄與局部congestion，狀態為PASS WITH THIN MARGIN。未產生BIT、
  未保留matching production HWH且未連板，PS driver與DDR/DMA end-to-end仍未驗證。

- 2026-09-06：將production accelerator推進到full Zynq pre-implementation。
  `accelerator_system_top`與PYNQ-Z1 BD已整合AXI4-Lite control、mailbox、兩個DMA、
  HP0..HP3、四路IRQ及split reset。Fresh control XSim與BD validation PASS；Vivado
  2018.3 global synthesis、CDC與timing coverage檢查完成，資源全部低於80% gate。
  Full-design setup WNS仍為-0.321 ns，故狀態明確維持pre-implementation：未執行
  place/route、未產生v4 BIT/HWH、未執行driver或實板功能／效能測試。

- 2026-09-03：完成parameter BRAM Stage 2 artifact generation，但實板smoke在program前
  BLOCKED。Frozen commit `78c86f3`的memory/BD inputs經byte比對後，以Windows Vivado
  2018.3 fresh build重建PYNQ-Z1 preset BD、validate/synth/opt/place/route，再執行
  `write_bitstream`並輸出matching HWH/LTX。Post-route setup/hold為+0.964/+0.019 ns，
  0 failing endpoints、0 unrouted、0 blocking DRC；BIT/HWH/LTX SHA-256與build metadata
  已保存。Python 20/20及Stage-2-only mock通過。因沒有明確PYNQ-Z1 endpoint，未掃描、
  未猜IP/認證、未連線/program/讀register；Stage 2 counters、5筆readback、release/
  cleanup皆無board evidence，Stage 1未執行且不允許進入。

- 2026-09-02：完成parameter BRAM PYNQ-Z1完整BD pre-bitstream implementation。
  Windows Vivado 2018.3從乾淨temp套用PYNQ-Z1 preset重建PS7、100 MHz reset/GP0/HP0、
  4 KiB control address與5-probe ILA，完成validate、synthesis、opt/place/route。
  Post-route setup WNS +0.964 ns、hold WHS +0.019 ns，兩者0 failing endpoints；8,714/
  8,714 routable nets完成，`check_timing`無unconstrained internal endpoint。完整資源為
  3,814 LUT、5,218 FF、73 RAMB36+1 RAMB18與1 DSP，ILA+debug hub成本為1,674 LUT、
  3,280 FF及9.5 BRAM36-equivalent。最終DRC／methodology無Error或Critical violation；
  CDC warnings全在generated debug hub。先前`REQP-1839`以AXI-R ingress register修正後
  乾淨重跑消失。`PSU-1/PSU-2` DQS值確認來自installed preset且在PS7 schema允許範圍，
  保留為板測風險而不waive。Python 18/18及real-v3 13/13、兩個相關XSim通過；Icarus
  因未安裝無新run。Gate為PASS WITH RISKS；沒有執行`write_bitstream`或連接板子。

- 2026-09-02：完成parameter BRAM pre-bitstream bring-up。新增可綜合4 KiB
  AXI-Lite wrapper與single-clock top，service以明確ports輸出raw-loader diagnostics；
  v3 golden固定13筆readback並由Python逐byte驗證。Windows Vivado 2018.3以real image
  通過stage 2的21,056 B/2,632 beats/165 bursts/0 LUT及stage 1的219,648 B/
  27,456 beats/1,717 bursts/255 LUT、13/13 readback和error/recovery cases；完整root
  RTL regression為25/25 PASS。XC7Z020 10 ns integrated RTL OOC為1,479 total LUT
  （1,822 LUT primitives）、1,215 FF、1 DSP、64 RAMB36、WNS +1.890 ns；PYNQ-Z1
  preset、100 MHz GP0/HP0、
  `0x43C00000/4 KiB`與5-probe ILA的BD Tcl validation PASS。PYNQ driver mock包含
  allocate/flush/barrier/poll、dynamic burst count及safe cleanup，Python合計18/18。
  未執行implementation、write_bitstream或實板；DDR preset DQS critical warnings與
  ARM target helper仍留待下一關。

- 2026-09-02：凍結parameter BRAM第一個板上bring-up驗證契約。固定PYNQ-Z1
  FCLK0 100 MHz、GP0 32-bit AXI4-Lite、HP0 64-bit read-only parameter path、256 KiB/
  64-RAMB36 cache、register ABI、PYNQ buffer flush/barrier、stage 2 -> stage 1
  readback cases、typed recovery、PASS counters與ILA probes。盤點確認目前沒有可重用
  board BD/bitstream/PYNQ driver，且existing golden JSON尚缺request-level 128-bit
  vectors；本次只新增文件，未產生bitstream、未板測、未修改`upstream/`。

- 2026-09-02：完成全資料夾重新審查（程式／RTL審查基準`3457166`）。本機重跑Python 12/12與
  reference 13/13 PASS，formal PE baseline archive 111/111 checksums OK，本頁82/82
  local links存在；Icarus/Vivado在目前shell不可用，故HDL/OOC只核對已commit證據。
  依latest manifest/handoff確認8個formal PE modules，並新增intended-count分析合計；
  同時標示PE subtree規則/spec仍停在4 modules、RTL-only commit `3457166`的
  `pe_spike_decision.v`仍非formal checkpoint、`upstream/` 21個dirty files為EOL-only、
  legacy estimator仍包含已被PS/mailbox分工取代的PL LayerNorm假設。完整accelerator
  integration、CDC、AXI IP、
  implementation與板測仍未完成。

- 2026-09-02：依memory設計準則完成第一版correctness baseline。保留immutable
  `parameters.bin`並產生1,053,056-byte consumer-native v3 image、layout/golden/SHA與
  synthesizable stage table；最大stage 219,648 B可放入單一256 KiB cache。
  `memory_service`完成AXI AR/R load、ownership、2x64->128 weights、5,792/1,120-bit
  parameters、LUT、tag/backpressure/error；4 KiB LayerNorm mailbox完成雙slot
  frame/claim/commit/release與exact 64/782-byte ABI。Python全套12/12、Icarus全RTL
  24/24與memory-only Vivado XSim 3/3 PASS。Vivado 2018.3 XC7Z020 10 ns OOC中，
  service使用5,999 LUT、6,580 FF、1 DSP、64 RAMB36、WNS +1.858 ns；mailbox使用
  1,120 LUT、801 FF、1 RAMB36、WNS +1.647 ns。結果不含AXI BRAM Controller/
  interconnect、global integration、place/route、driver或板測。

- 2026-09-01：修訂production memory transport：保留PS DDR -> custom AXI read ->
  256 KiB provisional parameter cache；將每frame 64-byte fullband projection與
  782-byte normalized subband LayerNorm round trip改為4 KiB dual-slot BRAM mailbox，
  CPU經`M_AXI_GP`/AXI BRAM Controller直接MMIO，繞過DDR controller與AXI DMA；
  external fullband ingress/final egress才使用AXI DMA。這是architecture文件更新，
  mailbox RTL、Vivado inference、driver/MMIO latency與板測仍是UNKNOWN。

- 2026-09-01：定案production memory transport：PL靜態parameter由PS DDR經
  `memory.v` custom AXI read載入BRAM，再由`memory_service`供應native介面；當時
  runtime feature/result全走Xilinx AXI DMA/64-bit AXI4-Stream。此初始baseline的
  LayerNorm intermediate部分已由上列mailbox修訂取代；external ingress/final egress
  仍保留DMA。當時只有文件與architecture decision，未新增RTL、Vivado或板測證據。

- 2026-09-01：完成單一bit-exact GSN/GSU neuron cell。真實`parameters.bin`的兩個
  fullband cells各涵蓋320個channel並各加16個stress vectors，Windows Vivado 2018.3
  XSim 672/672 PASS、固定latency 100 cycles、96筆result stalls與63個clipped vectors。
  XC7Z020 5 ns OOC為1,172 LUT、1,484 FF、5 DSP、1 BRAM18、WNS +0.263 ns。此結果
  不包含matrix MAC/memory/AXI，production需共享16 PE與4-lane RQ而非複製320 cells。

- 2026-09-01：明確取消一般工作的 task card；開始修改前固定確認本頁與 PYNQ-Z1
  feasibility checklist，完成後以 Git commit 保存更新。

- 2026-09-01：簡化共編流程；Git commit 成為每次完成更新的唯一固定紀錄要求，
  task、handoff、decision、`PROJECT_STATUS.md`、branch 與 PR 改為按需使用。

- 2026-09-01：完成當時experimental PE Array具名operator RTL與combined support
  XSim（不等於formal baseline）；Hybrid MAC 4,109 vectors PASS，5 ns OOC為
  87 LUT、68 FF、1 DSP、WNS +0.270 ns。使用
  真實`parameters.bin`完成LayerNorm-reference -> 64x320 GSU1 -> 320x320 GSU2 ->
  320x64 projection -> DF 5/3/1的10,651-command/85-tile XSim PASS。16-MAC shell
  OOC為1,346 LUT、1,050 FF、16 DSP、0 BRAM、WNS +0.270 ns。完整connected GSU、
  memory/AXI、multi-frame、implementation與板測仍未完成。

- 2026-09-01：完成global `fsm.v`：fullband三stage、PL->PS->PL、subband
  GSU1/GSU2/projection、DeepFilter與output共13個控制state；共享單PE和實驗性
  三branch平行模式皆由`tb_fsm`驗證，完整XSim 22/22 PASS。FSM-only XC7Z020
  10 ns OOC為121 LUT、67 FF、0 DSP/BRAM、WNS +4.792 ns。三路GSU2 raw banks
  分析估算102/140 BRAM36，完整三路datapath仍屬UNKNOWN/HIGH RISK，預設不啟用。

- 2026-09-01：完成獨立4-lane Local Requant Bank：2,112 packets／4,149 active
  results與standalone integer reference bit-exact，XSim確認latency 9、bank II=1、
  4 results/cycle及共同backpressure；Vivado 2018.3 OOC使用2,167 LUT、1,732 FF、
  16 DSP，5 ns WNS +0.263 ns。4 lanes定為第一版baseline，尚未開始`pe_hybrid_mac`。

- 2026-09-01：記錄FPGA權重寫入建議：原始row-major `parameters.bin`保持不變，
  首選由host離線generator產生`{source_index,row_tile,lane}`的FPGA-ready v3 image；
  PS啟動時repack只作開發fallback，不在PL內做transpose。另明確註記layout重排本身
  不會減少完整stage preload的DDR bytes，仍需active-source按需fetch或tile cache。
- 2026-09-01：完成23個synthesizable RTL module的PYNQ-Z1 retroactive audit；只有
  `pe_requant_lane`具單lane完整XSim/OOC證據，legacy GSU/fullband與預設512 KiB
  cache判為blocked。逐tensor驗證2,193,288-byte `parameters.bin`，20 matrix × 5
  selected-index real-weight tests全部等於dense binary reference；約6.25% active的16個
  eligible matrix合計logical reads由54,304降至3,394。v3 physical order定為
  `{source_index,row_tile,lane}`；尚無DDR/RTL/board speedup證據。
- 2026-09-01：建立外層 Git initial baseline `124a771`，以 gitlink 保存
  `upstream` HEAD 且不碰其 dirty changes；新增 PYNQ-Z1 Gate A/B/C checklist，
  後續所有模塊在實作前必須先完成 scaled resource/bandwidth/timing feasibility。
- 2026-09-01：完成獨立 `pe_requant_lane`：standalone reference 與 XSim
  5,155/5,155 PASS，exact latency 9、II=1；Vivado 2018.3 OOC 使用 475 LUT、
  431 FF、4 DSP，5 ns WNS +0.263 ns、estimated Fmax 211.104 MHz。未開始下一模塊。
- 2026-09-01：將規格中的 `pe_membrane_update` 更正為 control-only
  `pe_membrane_sequencer`；只允許 phase/register/mask/PE-control/RQ-scheduling，
  明確禁止 dedicated multiplier、requant lane、MAC 或 membrane arithmetic lane。
- 2026-09-01：建立隔離的 `rtl/pe_array/` scaffold、固定 incremental module order、
  provisional interfaces 與逐模塊 RTL/TB/Python/Vivado gate；本 checkpoint 未新增
  `.v/.sv`，也沒有功能、resource 或 timing 證據。
- 2026-09-01：安全分類 Memory-only upload bundle；匯入 64-bit AXI read loader/
  BRAM raw cache、12-stage compact image、generator 與 TB。Python image test 2/2
  PASS 且三個 generated artifacts 可 byte-exact 重建；確認 v2 row-major layout、
  128-bit weight/parameter adapter 與 fullband stage barrier 仍是整合 blocker。
- 2026-09-01：新增 32-bit AXI4-Lite control、64-bit AXI4-Stream INT8
  ingress/egress 與 64->128-bit weight loader；三個 AXI testbench 及既有 RTL
  在 Windows Vivado 2018.3 XSim 完成 20/20 PASS，Python reference 13/13 PASS。
- 2026-09-01：確認 subband frequency unfold、concatenation、LayerNorm 與 INT8
  packing 放在 PYNQ-Z1 PS CPU；PL 接收 46/94/158-element normalized INT8
  vectors。fullband LayerNorm 暫時維持外部 PC/host 邊界。
- 2026-09-01：建立本進度入口；彙整至 fullband GSU1 -> GSU2 -> projection
  行為原型，保存設計簡報副本，記錄最新 XSim 17/17 與 Python 13/13 結果。
