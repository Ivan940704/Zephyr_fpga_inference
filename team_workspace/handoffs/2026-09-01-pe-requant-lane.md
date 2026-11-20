# Handoff: `pe_requant_lane`

- Date: 2026-09-01 (Asia/Taipei)
- Owner: Ivan Huang (PE Array), with Codex assistance
- Task: `team_workspace/tasks/2026-09-01-pe-array-independent-development.md`
- Status: module checkpoint complete; no next module started

## Changed files

- `rtl/pe_array/rtl/arithmetic/pe_requant_lane.sv`
- `rtl/pe_array/reference/pe_requant_lane_reference.py`
- `rtl/pe_array/tb/vectors/pe_requant_lane_vectors.txt`
- `rtl/pe_array/tb/unit/tb_pe_requant_lane.sv`
- `rtl/pe_array/scripts/sim/run_pe_requant_lane_xsim.tcl`
- `rtl/pe_array/scripts/synth/synth_pe_requant_lane_ooc.tcl`
- `rtl/pe_array/constraints/pe_requant_lane_200mhz.xdc`
- `rtl/pe_array/reports/pe_requant_lane/*`
- PE Array task and `PROJECT_STATUS.md`

No file under existing `rtl/leaf/`, `rtl/sparse/`, or `upstream/` was modified.

## Verified results

- Standalone reference: 5,155 vectors verified, SHA-256
  `03a12ebc40630f0e233703cccae5106556d7000a24a1a36431ae44f7d56cd1b8`.
- XSim 2018.3: 5,155/5,155 PASS with edge/random values and randomized
  ready/valid backpressure.
- Exact pipeline latency: 9 cycles.
- Initiation interval: 1 cycle without downstream stall.
- OOC synthesis on `xc7z020clg400-1`: 475 LUT, 431 FF, 4 DSP48E1.
- 5 ns timing: WNS +0.263 ns, TNS 0, estimated Fmax 211.104 MHz; target met.

The initial unpipelined wide-multiplier implementation failed WNS at -2.239 ns.
It was replaced with four registered 16/17-bit partial products and pipelined
reconstruction, then the full reference/XSim/synthesis sequence was rerun.

## Limitations

- Current evidence is behavioral XSim plus post-synthesis OOC timing, not
  placement/routing, integrated PE Array timing, or board measurement.
- WSL does not currently contain PyTorch; the optional live invocation of the
  upstream class was not rerun. The standalone function directly transcribes
  `IntegerRequantizer.forward`, and the existing project record has the related
  upstream unit test in its 13/13 PASS set.
- XSim waveform setup reports display-limit warnings for large TB arrays; no
  compile, elaboration, arithmetic, tag, or handshake failure remains.

## Next action

Review and accept this module checkpoint. Do not begin
`pe_local_requant_bank_4lane` until explicitly requested.

