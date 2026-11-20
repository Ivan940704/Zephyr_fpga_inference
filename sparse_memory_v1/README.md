# Sequential v4 sparse memory v1

This subtree is the isolated development package for
`sequential-v4-sparse-load-v1`. It investigates stage-time active-list union
and canonical-address scatter fill while leaving the existing production
memory and accelerator-top trees untouched.

The imported dense baseline, frozen PE RTL, schedule controller, and v4 image
are copied under `imports/` and pinned by `IMPORT_SHA256SUMS`. New design files,
tests, runners, evidence, and board support live only in this subtree.

The current objective is to reduce accepted AXI read bytes. It is not a claim
of accelerator-top timing closure, board bandwidth, real-time factor, power,
or audio quality.

Run host checks from the repository root with:

```bash
python3 -m pytest -q sparse_memory_v1/tests
python3 sparse_memory_v1/scripts/check_isolation.py
python3 sparse_memory_v1/scripts/run_dense_baseline.py
```
