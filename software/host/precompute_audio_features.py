#!/usr/bin/env python3
"""Precompute Zephyr STFT and magnitude features on an x86 host."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from software.audio_feature_bundle import build_feature_bundle  # noqa: E402


def default_bundle_name(path: Path) -> str:
    parent = path.resolve().parent.name
    return parent if parent.startswith("fileid_") else path.stem


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-wav", type=Path, action="append", required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()

    names: set[str] = set()
    records = []
    for input_wav in args.input_wav:
        name = default_bundle_name(input_wav)
        if name in names:
            parser.error(f"duplicate output bundle name: {name}")
        names.add(name)
        record = build_feature_bundle(input_wav, args.output_root / name)
        records.append(record)
        print(
            "HOST_FEATURE_BUNDLE "
            + json.dumps(
                {
                    "bundle_dir": record["bundle_dir"],
                    "frames": record["frame_count"],
                    "host_compute_elapsed_s": record["host_compute_elapsed_s"],
                    "metadata_sha256": record["metadata_sha256"],
                    "source_sha256": record["source_sha256"],
                },
                sort_keys=True,
            ),
            flush=True,
        )
    manifest = {
        "schema": "zephyr.host-feature-run.v1",
        "status": "PASS",
        "bundle_count": len(records),
        "records": records,
    }
    args.output_root.mkdir(parents=True, exist_ok=True)
    (args.output_root / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print("HOST_FEATURE_RUN_RESULT " + json.dumps(manifest, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
