#!/usr/bin/env python3
"""Extract the small PS LayerNorm runtime bundle from the model archive."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


DTYPES = {"float32": "<f4", "float64": "<f8"}


def read_tensor(blob: bytes, metadata: dict) -> np.ndarray:
    dtype = DTYPES.get(metadata["dtype"])
    if dtype is None:
        raise ValueError(f"unsupported runtime tensor dtype {metadata['dtype']}")
    start = int(metadata["offset"])
    end = start + int(metadata["nbytes"])
    raw = blob[start:end]
    if hashlib.sha256(raw).hexdigest() != metadata["sha256"]:
        raise ValueError("runtime tensor checksum mismatch")
    return np.frombuffer(raw, dtype=dtype).reshape(metadata["shape"]).copy()


def build(manifest_path: Path, output_path: Path) -> None:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    blob_path = manifest_path.parent / manifest["storage"]["file"]
    blob = blob_path.read_bytes()
    if hashlib.sha256(blob).hexdigest() != manifest["storage"]["sha256"]:
        raise ValueError("source parameter archive checksum mismatch")
    unlowered = manifest["unlowered_parameters"]
    arrays = {
        "fb_weight": read_tensor(blob, unlowered["fb_model.pre_layer_norm.weight"]),
        "fb_bias": read_tensor(blob, unlowered["fb_model.pre_layer_norm.bias"]),
    }
    fb_first = "fb_model.sequence_model.layers.0.cell"
    arrays["fb_input_scale"] = read_tensor(
        blob, manifest["operators"][fb_first]["tensors"]["input_scale"]
    )
    arrays["fb_projection_scale"] = read_tensor(
        blob, manifest["operators"]["fb_model.proj"]["tensors"]["output_scale"]
    )
    for index in range(3):
        prefix = f"sb_model.sb_models.{index}"
        arrays[f"sb{index}_weight"] = read_tensor(
            blob, unlowered[f"{prefix}.pre_layer_norm.weight"]
        )
        arrays[f"sb{index}_bias"] = read_tensor(
            blob, unlowered[f"{prefix}.pre_layer_norm.bias"]
        )
        arrays[f"sb{index}_input_scale"] = read_tensor(
            blob,
            manifest["operators"][f"{prefix}.sequence_model.layers.0.cell"]
            ["tensors"]["input_scale"],
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    np.savez(output_path, **arrays)
    print(
        f"runtime_bundle={output_path} bytes={output_path.stat().st_size} "
        f"sha256={hashlib.sha256(output_path.read_bytes()).hexdigest()}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.manifest, args.output)


if __name__ == "__main__":
    main()
