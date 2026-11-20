# Handoff: PE Array operators and full-shape small model

- Branch: `codex/pe-array-small-model`
- Scope completed: remaining named PE operator RTL, combined support regression,
  16-MAC integration shell, real-parameter full-shape one-frame small-model
  regression, and representative XC7Z020 OOC synthesis.
- Key RTL: `rtl/pe_array/rtl/{pe,nonlinear,stream,index,control,top}/`.
- Reproduction:
  1. `python3 rtl/pe_array/reference/pe_hybrid_mac_reference.py`
  2. `python3 rtl/pe_array/reference/pe_support_reference.py`
  3. `python3 rtl/pe_array/reference/pe_small_model_reference.py`
  4. Run the matching Tcl files under `rtl/pe_array/scripts/sim/` with Windows
     Vivado 2018.3 and `rtl/pe_array` as the first Tcl argument.
  5. Run `synth_pe_hybrid_mac_ooc.tcl` and `synth_pe_array_top_ooc.tcl`.
- Results: Hybrid MAC 4,109 vectors PASS; support regression PASS; full-shape
  10,651-command/85-tile regression PASS. Hybrid MAC OOC is 87 LUT/68 FF/1 DSP,
  WNS +0.270 ns. 16-MAC shell is 1,346 LUT/1,050 FF/16 DSP/0 BRAM,
  WNS +0.270 ns at 5 ns.
- Existing Local RQ evidence remains 2,167 LUT/1,732 FF/16 DSP, WNS +0.263 ns.
- Not verified: a fully connected GSU postprocess datapath using production
  memory/AXI, recurrent multi-frame trace, complete intended-count OOC including
  cache/AXI, place-and-route, bitstream, RTF, power or board audio quality.
- Next owner should connect the real v3 source-major memory service and make the
  full GSU postprocess flow consume/produce RTL streams before any board claim.
