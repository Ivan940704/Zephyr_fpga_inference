#!/usr/bin/env python3
"""Add image-v5 DMA-ready packets to existing checksummed feature bundles."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from software.audio_feature_bundle import (  # noqa: E402
    PACKED_ABI,
    SCHEMA,
    load_feature_bundle,
    pack_magnitude_frames_q12,
    pack_spectrum_frames_int8,
    sha256_file,
)


def upgrade_bundle(source_dir: Path, output_dir: Path) -> dict[str, object]:
    """Create a self-contained v2 bundle without recomputing STFT/magnitude."""

    source_dir = source_dir.resolve()
    output_dir = output_dir.resolve()
    if output_dir.exists() and any(output_dir.iterdir()):
        raise ValueError(f"output directory is not empty: {output_dir}")
    bundle = load_feature_bundle(source_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    metadata = json.loads(json.dumps(bundle.metadata))
    for name in ("spectrum", "magnitude"):
        record = metadata[name]
        source = source_dir / record["file"]
        destination = output_dir / record["file"]
        shutil.copyfile(source, destination)
        record["sha256"] = sha256_file(destination)

    started = time.perf_counter()
    magnitude_q12 = pack_magnitude_frames_q12(bundle.magnitude)
    spectrum_q = pack_spectrum_frames_int8(bundle.spectrum)
    magnitude_path = output_dir / "magnitude_q12.npy"
    spectrum_path = output_dir / "spectrum_q.npy"
    np.save(magnitude_path, magnitude_q12, allow_pickle=False)
    np.save(spectrum_path, spectrum_q, allow_pickle=False)
    metadata.update(
        {
            "schema": SCHEMA,
            "packed_abi": PACKED_ABI,
            "host_dma_packing_elapsed_s": float(time.perf_counter() - started),
            "magnitude_q12": {
                "file": magnitude_path.name,
                "dtype": "uint8",
                "shape": list(magnitude_q12.shape),
                "sha256": sha256_file(magnitude_path),
            },
            "spectrum_q": {
                "file": spectrum_path.name,
                "dtype": "int8",
                "shape": list(spectrum_q.shape),
                "sha256": sha256_file(spectrum_path),
            },
        }
    )
    metadata_path = output_dir / "metadata.json"
    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return {
        "bundle_dir": str(output_dir),
        "frame_count": metadata["frame_count"],
        "source_sha256": metadata["source_sha256"],
        "metadata_sha256": sha256_file(metadata_path),
        "host_dma_packing_elapsed_s": metadata["host_dma_packing_elapsed_s"],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--file-ids", type=int, nargs="+", required=True)
    args = parser.parse_args()
    if len(args.file_ids) != len(set(args.file_ids)):
        parser.error("--file-ids must be unique")
    records = []
    for file_id in args.file_ids:
        name = f"fileid_{file_id:03d}"
        record = upgrade_bundle(args.source_root / name, args.output_root / name)
        records.append(record)
        print("UPGRADED_FEATURE_BUNDLE " + json.dumps(record, sort_keys=True), flush=True)
    manifest = {
        "schema": "zephyr.host-feature-upgrade.v1",
        "status": "PASS",
        "records": records,
    }
    args.output_root.mkdir(parents=True, exist_ok=True)
    (args.output_root / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
