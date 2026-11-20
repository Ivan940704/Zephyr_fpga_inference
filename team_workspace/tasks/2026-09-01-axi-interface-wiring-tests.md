# Task: 建立 AXI interface 接線與 testbench checkpoint

- Owner: Codex
- Status: complete
- Branch: `codex/axi-interface-wiring-tests` requested; no branch can be
  created before the outer repository has an initial commit.
- Scope:
  - 實作 64-bit AXI4-Stream INT8 ingress/egress adapters，並以 loopback 驗證
    PS/DMA-like stream 到 native `valid/ready` 再回到 AXI stream 的接線。
  - 實作 64-bit AXI4-Stream 到 128-bit、16-lane weight word loader，接到既有
    ping-pong weight buffer 驗證資料順序與 bank load。
  - 實作最小 32-bit AXI4-Lite control/status register block。
  - 建立 self-checking testbenches，涵蓋 backpressure、source gaps、`TKEEP`、
    `TLAST`、獨立 AW/W channels、`WSTRB`、連續 transaction 與 reset。
  - 將新模塊加入 Icarus 與 Windows XSim regression。
- Out of scope:
  - Vivado block design、Xilinx AXI DMA IP、Zynq PS configuration、driver、
    bitstream、physical PYNQ-Z1 transfer measurement。
  - 將 AXI adapters 接進 fullband GSU datapath 或建立最終 `top.v`。
  - 修改 dirty `upstream/` nested repository。
- Acceptance checks:
  - [x] AXI4-Stream loopback 不丟失、不重複、不亂序，且 packet boundary 正確。
  - [x] 1/8/13/46/94/158-byte packets 與 non-contiguous `TKEEP` 通過。
  - [x] AXI weight loader 正確將兩個 64-bit beats 重組成一個 128-bit word。
  - [x] AXI4-Lite register read/write、AW/W skew、`WSTRB`、sticky status 與 pulses 通過。
  - [x] Python reference 13/13 與 Windows XSim regression 20/20 通過並留存 log。
  - [x] `make test` 已嘗試；Python 通過，但 WSL 未安裝 `iverilog`，限制已記錄。
  - [x] 更新 `PROJECT_STATUS.md`、RTL README 與 handoff。
