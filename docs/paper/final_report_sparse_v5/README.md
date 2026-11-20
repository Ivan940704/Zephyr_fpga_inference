# Sparse-v5 paper result package

This directory supplements the Zephyr paper with the completed sparse-v5
32-PE board experiment.  It does not replace the preserved image-v5 baseline.

## Files

- `final_report_sparse_v5.md`: complete Traditional-Chinese final report and
  evidence boundaries.
- `tables_sparse_v5.tex`: editable `booktabs` LaTeX tables for implementation,
  system results, baseline comparison, and sparse diagnostics.
- `paper_measurement_notes_sparse_v5.tex`: short English measurement notes for
  author review and rewriting; not a complete manuscript section.
- `evidence_summary_sparse_v5.json`: frozen sparse-v5 machine-readable evidence.
- `evidence_summary_image_v5.json`: frozen image-v5 comparison evidence.
- `verify_report.py`: checks headline values and selected derived comparisons
  against the frozen JSON files.
- `schematic/`: Vivado 2018.3 post-synthesis accelerator, PE/sparse-memory,
  and PL LayerNorm schematics in zoomable SVG/PDF and rendered PNG formats.
  The Tcl exporters load the preserved sparse-v5 post-synthesis DCP directly.
- `figures/`: a clean, paper-ready module-level architecture diagram traced
  from production RTL, supplied as editable SVG and rendered PNG.

## Evidence identity

- Sparse image ABI: `0x00050002`
- Sparse implementation commit: `c9e227f88e4880348eaee974f8fb0c9573e7416c`
- Validated source commit: `d4400a0`
- Result-record commit: `ca152b3`
- Sparse evidence SHA-256:
  `c3cd12954c10227da9d6503e6ffca042fda78ba4d6b7474a79cd634176c95ade`
- Image-v5 evidence SHA-256:
  `79e79e7e577ae101d65f56e052b5cac431d4a2dd2ab12ce416c5984ed15b6065`

The source sparse-v5 run is retained at
`outputs/latency/2026-09-14-sparse-v5-32pe/` in the result workspace.  Existing
image-v5 paper tables are intentionally left untouched so both versions remain
auditable.

## Integration notes

Load `booktabs` before including `tables_sparse_v5.tex`.  Keep SI-SDR distinct
from SI-SNR.  Cite the 9.344 mJ/frame value only as a vectorless on-chip energy
estimate; no physical board-rail power measurement is available.  Keep the
five-file sampled sparse profile separate from the profiling-off 100-file
latency result.

Run the local consistency check with:

```text
python3 docs/paper/final_report_sparse_v5/verify_report.py
```

## Vivado post-synthesis schematics

The source checkpoint is:

```text
C:/tmp/zv5-sparse-sim/zephyr_full_bd/checkpoints/zephyr_full_post_synth.dcp
```

`schematic/export_module_views.tcl` creates the readable hierarchy views;
`schematic/export_synth_schematics.tcl` creates the complete local-net views.
The complete views are intentionally dense because Vivado includes every
post-synthesis bus and connection. Use the SVG or PDF outputs for zooming.
For papers and presentations, use
`figures/zephyr_sparse_v5_hardware_modules.png`; use the matching SVG when
editing labels or exporting at another resolution.
