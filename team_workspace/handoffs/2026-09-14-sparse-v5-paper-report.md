# Sparse-v5 paper report handoff

Date: 2026-09-14

Owner: Codex

Branch: `codex/sparse-v5-paper-report`

Baseline result record: `ca152b3`

## Delivered

- `docs/paper/final_report_sparse_v5/final_report_sparse_v5.md`
- `docs/paper/final_report_sparse_v5/tables_sparse_v5.tex`
- `docs/paper/final_report_sparse_v5/paper_measurement_notes_sparse_v5.tex`
- `docs/paper/final_report_sparse_v5/evidence_summary_sparse_v5.json`
- `docs/paper/final_report_sparse_v5/evidence_summary_image_v5.json`
- `docs/paper/final_report_sparse_v5/verify_report.py`
- `docs/paper/final_report_sparse_v5/README.md`
- `docs/paper/final_report_sparse_v5/schematic/`: Vivado-generated
  post-synthesis hierarchy and complete-net schematics, plus reproducible Tcl
  exporters.
- `docs/paper/final_report_sparse_v5/figures/`: clean RTL-derived hardware
  module architecture in editable SVG and rendered 2200 x 1320 PNG.

The package records the completed 100-file sparse-v5 board result and compares
it with the frozen image-v5 baseline.  Existing paper assets were not modified.

## Headline result

- 100/100 PASS; 426,196 frames and 3,408.768 s evaluated audio.
- Mean START-to-output / iteration: 5.3943 / 5.8076 ms.
- Sustained board-loop RTF: 0.728054.
- Enhanced SI-SDR: 14.5120 dB; 100/100 outputs bit-exact vs image-v5.
- Routed resources: 42,773 LUT, 45,344 FF, 76 BRAM36, 7 BRAM18, 68 DSP.
- Timing: WNS +0.251 ns; guardbanded WNS/WHS +0.001/+0.002 ns at 100 MHz.
- Estimated on-chip energy: 9.344 mJ per complete frame iteration.

## Verification

```text
python3 docs/paper/final_report_sparse_v5/verify_report.py
PASS: sparse-v5 paper metrics match the frozen evidence summaries
```

The checker validates the evidence SHA-256 hashes, core experiment identity,
derived A/B reductions, energy arithmetic, required report/table values, and
basic LaTeX brace balance.  `git diff --check` passes.

Vivado 2018.3 also reopened the preserved 15,631,079-byte post-synthesis DCP
and exported accelerator, PE/sparse-memory and PL LayerNorm views in SVG and
PDF. The PDFs were rendered to PNG and visually checked; the complete-net
views are dense by construction, while the hierarchy views retain module
boundaries and port names for zoomed inspection.

The additional paper figure was manually traced from the production
`accelerator_system_top`, `accelerator_top`, sparse-memory subsystem and PL
LayerNorm hierarchy. Its SVG parses successfully and its PNG was visually
checked for clipping, label overlap and source-consistent data/control flow.

## Evidence boundaries

- Main latency/RTF/quality: profiling-off 100-file physical-board run.
- Sparse traffic and MAC skip: separate five-file run, 1,453 hardware-counter
  samples taken once per 16 frames.
- LUT/FF/BRAM/DSP/WNS/WHS: full-system post-route reports.
- Power/energy: Vivado vectorless on-chip estimate, not board-rail measurement.
- SI-SDR is not SI-SNR.  PESQ, STOI, DNSMOS and 100-file firing rate remain
  unmeasured in this result package.
