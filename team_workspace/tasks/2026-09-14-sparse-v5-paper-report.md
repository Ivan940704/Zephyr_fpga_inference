# Sparse-v5 paper final report

- Owner: Codex
- Branch: `codex/sparse-v5-paper-report`
- Baseline: completed sparse-memory result commit `ca152b3`, image ABI
  `0x00050002`.
- Scope: create an evidence-backed `final_report_sparse_v5` package for paper
  integration, covering LUT, FF, BRAM, DSP, timing, energy, SI-SDR, latency,
  RTF, sparse-memory traffic and comparison with image-v5.
- Inputs:
  - `outputs/latency/2026-09-14-sparse-v5-32pe/REPORT.md`
  - `outputs/latency/2026-09-14-sparse-v5-32pe/SUMMARY.json`
  - `outputs/checkpoints/2026-09-14-sparse-v5-32pe/`
  - prior paper notes and image-v5 result tables in the outer report workspace.
- Output: `docs/paper/final_report_sparse_v5/` containing a Traditional-Chinese
  report, native LaTeX tables/paragraph snippets, a machine-readable summary
  and evidence notes.
- Acceptance:
  - Every numeric claim is traceable to the completed 100-file board run,
    fixed-five sampled profile, full-system post-route report, or vectorless
    power estimate.
  - Board measurement, sampled profiling, routed implementation and estimated
    energy are visibly separated.
  - SI-SDR is not renamed SI-SNR; board-loop RTF is not presented as a hard
    per-frame deadline guarantee.
  - Existing image-v5 paper assets remain unchanged.
  - Generated JSON/LaTeX/Markdown are checked for internal numeric consistency.

## Completion

- Status: complete.
- Delivered the Traditional-Chinese report, four native LaTeX tables, English
  author-editing measurement notes, frozen sparse-v5/image-v5 evidence copies,
  and a repeatable consistency checker.
- Verification: `python3 docs/paper/final_report_sparse_v5/verify_report.py`
  returned PASS; Git whitespace checks also pass.
- Limitations: energy remains a medium-confidence Vivado vectorless on-chip
  estimate; the five-file sparse counters are a diagnostic sample rather than
  a 100-file firing-rate measurement; no physical board-rail power, SI-SNR,
  PESQ, STOI, or DNSMOS result is claimed.
