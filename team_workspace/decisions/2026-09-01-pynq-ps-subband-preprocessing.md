# Decision: PYNQ PS 執行 subband preprocessing 與 LayerNorm

- Date: 2026-09-01
- Participants: Ivan, Codex
- Status: accepted
- Context:
  - Subband inference 需要先做 frequency unfold、把 noisy magnitude 與
    fullband feature concatenate，再執行各 subband 的 LayerNorm。
  - 三個 band 每 frame 分別有 `4 x 46`、`3 x 94`、`2 x 158` 個輸入元素，
    合計 9 個 LayerNorm vectors、782 個 elements。
  - 現有 parameter bundle 保留 LayerNorm float32 affine weight/bias，但尚未定義
    PL fixed-point LayerNorm arithmetic。
  - PYNQ-Z1 的 Zynq PS CPU 可以執行這些 routing 與 normalization 工作。
- Decision:
  - Subband frequency unfold、fullband/noisy feature concatenation、各 band
    LayerNorm 及送入 PL 前的量化/packing，放在 PYNQ-Z1 PS software。
  - PL 的 subband RTL boundary 接收已正規化、已量化的 INT8 vectors，尺寸為
    46、94 或 158；PL 不實作 subband LayerNorm RTL。
  - Fullband projection 的 64-element result 由 PL 提供給 PS；PS 依模型規格
    repeat/unfold 後建立 subband inputs，再傳回 PL 執行 subband GSU、projection
    與 DeepFilter。
  - 這個64-element PL->PS與782-element PS->PL LayerNorm round trip使用獨立4 KiB
    dual-port BRAM mailbox。CPU經PS `M_AXI_GP`與AXI BRAM Controller直接MMIO存取；
    不配置DDR buffer、不經DDR controller或AXI DMA。完整782-byte slot與frame ID
    atomic commit後，PL才能看見九個vectors。
  - 先前已決定放在外部 PC/host 的 fullband LayerNorm 暫時不變；若要移到
    PYNQ PS，另立決策並重新定義 fullband input boundary。
- Consequences:
  - 單frame的最低mailbox payload是PL->PS 64個fullband output elements，PS->PL
    782個normalized INT8 subband input elements；後者補2個zero bytes供word access，
    不含mailbox配置空間、control registers、magnitude source、weights與final results。
  - 126 frames/s 時，PS->PL normalized subband payload 的理論下限為
    98,532 bytes/s；頻寬本身不大，但每frame GP MMIO transaction、interrupt/polling、
    memory barrier、LayerNorm CPU latency與PL bubble必須在板上量測。
  - PS software與PL mailbox logic採兩個frame-level slots及單一owner狀態，讓frame N
    preprocessing與其他可獨立工作重疊；mailbox映射為device/uncached memory，無DDR
    flush/invalidate，但commit前後必須使用正確MMIO ordering barrier。
  - 舊估算中的 PL LayerNorm cycles、DSP 與 LUT 假設被本決策取代；系統 RTF
    必須改為 PL latency + PS preprocessing + PS/PL transfer 的實測 critical path。
- Still open:
  - PS LayerNorm 第一版使用 float32 reference、NEON vectorization 或 fixed-point。
  - mean/variance axis、epsilon、affine、rounding、saturation 與 INT8 output scale
    的 bit-exact contract。
  - AXI BRAM Controller與mailbox control register的最終base address、IRQ/polling、
    compiled-driver bulk MMIO方法及板上latency。
  - External fullband ingress/final result仍使用AXI DMA；其DDR layout、DMA mode、
    cache flush/invalidate與final-result packet ABI另在system block-design gate固定。
- Supersedes:
  - 先前把 subband preprocessing 模糊記成「PC/PS side」的邊界描述。
  - `ZEPHYR_FPGA_ESTIMATE.md` 內將 LayerNorm 計入 PL lane/cycle/resource 的假設。
