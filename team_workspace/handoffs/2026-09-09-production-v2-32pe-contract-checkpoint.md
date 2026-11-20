# Handoff: production-v2 32-PE contract checkpoint

- From: Codex
- To: user review, then the next Codex continuation
- Branch / commit: `codex/latency-experiment-32pe` / pending checkpoint commit
- Changed files: the 32-PE decision record, real-time integration report,
  machine-readable latency ledger, task progress, and this handoff
- Verification run: JSON parse, Git diff check, and frozen baseline-v1
  `sha256sum -c SHA256SUMS`
- Verified result: the requested 32-PE change has exact controller, memory,
  tile, tag/group, parameter-record, membrane, serializer, and CDF
  incompatibilities documented; baseline-v1 checksums remain unchanged
- Not verified / limitations: no Phase 5 RTL exists; the 8.077932/7.955733/
  7.838234 ms values are analytical means from an older file081 profile, not
  p99 or frozen-five-file PYNQ measurements; no full-Zynq BIT/HWH exists
- Next action: after explicit approval of the Phase 5A interface, implement
  only `rtl/pe_array/production_v2/rtl/pe/pe_hybrid_mac_array_32.v`, run its
  self-checking XSim and 100/102 MHz OOC checks, record latency/resources/
  timing, then stop for the next checkpoint review. Continue using the fixed
  five-file smoke set at intermediate board-capable gates. After the complete
  timing-clean release candidate exists, execute the separately recorded
  same-corpus 100-audio final validation and stage-profile pass.
