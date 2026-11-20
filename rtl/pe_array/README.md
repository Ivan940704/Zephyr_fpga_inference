# Independent PE Array workspace

This directory is the isolated development boundary for the new PE Array targeting
PYNQ-Z1 (`xc7z020clg400-1`) at 200 MHz. The named operator RTL and a full-shape
small-model verification checkpoint are now complete:

- `pe_requant_lane`: latency 9, II=1, 475 LUT, 431 FF, 4 DSP, WNS +0.263 ns;
- `pe_local_requant_bank_4lane`: latency 9, bank II=1, up to four results/cycle,
  2,167 LUT, 1,732 FF, 16 DSP, WNS +0.263 ns.
- `pe_hybrid_mac`: 4,109-vector XSim PASS; latency 1, II=1; 87 LUT, 68 FF,
  1 DSP, WNS +0.270 ns.
- support operators: real 255-entry sigmoid, serializer, shared requant,
  membrane sequencer, spike/index path and controller combined XSim PASS.
- 16-MAC arithmetic shell: 1,346 LUT, 1,050 FF, 16 DSP, WNS +0.270 ns.
- real-parameter shape smoke: LayerNorm-reference -> 64x320 GSU1 -> 320x320
  GSU2 -> 320x64 projection -> DeepFilter orders 5/3/1, 10,651 commands and
  85 tile checks PASS.
- standalone bit-exact GSN/GSU neuron cell: both fullband layers, 672
  real-channel/stress vectors XSim PASS, latency 100 cycles; 1,172 LUT, 1,484
  FF, 5 DSP, 1 BRAM18 and 5 ns WNS +0.263 ns. This is a verification instance;
  production must share the 16 PEs and four-lane RQ bank rather than replicate
  320 cells.

This is not a production top: memory/AXI wiring, connected GSU postprocessing,
multi-frame recurrent behavior, implementation and board measurement remain.

## Isolation contract

- All new PE-related RTL, testbenches, reference scripts, constraints, synthesis
  scripts, and reports live below this directory.
- New modules use the `pe_` prefix and are implemented independently.
- Existing modules under `rtl/leaf/`, `rtl/sparse/`, `rtl/gsu/`, and other project
  directories may be read as behavioral references, but are not modified,
  instantiated, included, or copied into this implementation.
- Upstream Python is the numerical source of truth where a bit-exact integer
  contract exists.
- The array controller and arithmetic shell exist; production memory/AXI
  integration remains deferred to the next checkpoint.

## Planned architecture

```text
16 x Hybrid MAC PE
        |
4-lane Local Requant Bank
        |
255-entry Sigmoid LUT
        |
same Hybrid MAC PEs reused for membrane update
        |
16-to-1 Serializer
        |
1-lane Shared Requant Engine
        |
QBN / Linear postprocess -> spike decision
        |
Active Index Writer / Buffer
```

## Directory layout

```text
rtl/pe_array/
|-- README.md
|-- spec/          architecture, interfaces, and verification gates
|-- rtl/
|   |-- arithmetic/  requantization arithmetic
|   |-- pe/          hybrid MAC and membrane reuse sequencer
|   |-- nonlinear/   sigmoid LUT
|   |-- stream/      serializer and shared postprocess stream
|   |-- index/       spike decision and active-index storage
|   |-- control/     deferred local/global controllers
|   `-- top/         deferred PE Array integration
|-- tb/
|   |-- unit/
|   |-- integration/
|   `-- vectors/
|-- reference/      Python vector generation and bit-exact checks
|-- scripts/
|   |-- sim/
|   `-- synth/
|-- constraints/    5 ns out-of-context clocks
|-- reports/        reviewed summaries; raw generated reports are ignored
`-- build/          generated Vivado/XSim outputs; ignored
```

Empty subdirectories are intentional and will be populated one verified module at
a time. The detailed order and provisional interfaces are in
[`spec/MODULE_DEVELOPMENT_PLAN.md`](spec/MODULE_DEVELOPMENT_PLAN.md).

## Per-module completion gate

A module is not considered complete, and work does not advance to the next one,
until all applicable items pass:

1. independent RTL implementation;
2. self-checking SystemVerilog testbench under `tb/unit/`;
3. bit-exact comparison with exported upstream Python integer vectors;
4. Vivado out-of-context synthesis for `xc7z020clg400-1` with a 5 ns clock;
5. reviewed latency/II, utilization, and timing summary under `reports/<module>/`;
6. task, handoff, and `PROJECT_STATUS.md` updated with measured evidence.
