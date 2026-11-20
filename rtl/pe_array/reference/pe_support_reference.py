#!/usr/bin/env python3
"""Export the real fullband-layer-1 sigmoid table for support-block XSim."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
manifest = json.loads((REPO / "upstream/parameters/manifest.json").read_text())
entry = manifest["operators"]["fb_model.sequence_model.layers.0.cell"]["tensors"]["sigmoid_lut"]
blob = (REPO / "upstream/parameters" / entry["file"]).read_bytes()
values = blob[entry["offset"]:entry["offset"] + entry["nbytes"]]
assert len(values) == 255
out = ROOT / "tb/vectors/pe_sigmoid_lut_fb1.hex"
out.write_text("\n".join(f"{v:02x}" for v in values) + "\n", encoding="ascii")
print(f"PE_SUPPORT_REFERENCE sigmoid_entries={len(values)} first={values[0]} mid={values[127]} last={values[-1]}")
