# PTQ audio evaluation

`ptq_audio_metrics.py` validates the fixed 100-triplet dataset before a long
board run and summarizes final enhanced outputs afterward.  It matches files
by numeric `fileid`, requires mono 16-bit PCM at 16 kHz, records SHA-256 and
sample counts, and never modifies source WAV files.

Create the immutable input inventory from WSL:

```bash
python3 software/evaluation/ptq_audio_metrics.py \
  --dataset-root /mnt/c/Users/User/Desktop/project/PTQ資料數據 \
  --output rtl/reports/accelerator_optimization_final/board_100_audio/dataset_manifest.json
```

For the final quality report, place each board output at
`<enhanced-root>/fileid_NNN/{enhanced.wav,metrics.json}` and add
`--enhanced-root <enhanced-root>`.  SNR and SI-SDR are built in.  STOI and PESQ
are evaluated only when the pinned packages in `requirements-ptq.txt` are
installed; otherwise their status is explicitly `BLOCKED`.

The 95% confidence intervals resample complete clips, not individual frames.
Board timing fields are copied from each matching `metrics.json` and remain
board evidence only when those files were produced on the named PYNQ image.

Single-clip STOI/PESQ failures (for example silent or too-short inputs) are
stored under `optional_metric_errors`; they do not abort the other clips and
are never replaced by a home-grown score.

Physical board-input power uses a separate evidence path. Fill the instrument
metadata and five idle/dense/sparse runs in
`rtl/reports/accelerator_optimization_final/power_physical/measurement_spec.template.json`,
then run:

```bash
python3 software/evaluation/power_trace_metrics.py \
  --spec /absolute/path/measurement_spec.json \
  --output /absolute/path/physical_power_result.json
```

Each CSV must contain strictly increasing `timestamp_s,power_w` rows covering
at least 60 seconds. The tool verifies sample rate, hashes every trace, uses
trapezoidal integration, subtracts pooled idle power, and reports mean,
standard deviation and Student-t 95% confidence intervals. It deliberately
does not consume or relabel Vivado vector-less estimates.
