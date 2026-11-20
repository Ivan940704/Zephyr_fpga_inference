#!/usr/bin/env python3
"""Reproduce the hash-pinned sequential-v4 dense baseline from local imports."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "imports" / "fixtures" / "v4"


def digest(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def reproduce() -> dict[str, object]:
    layout = json.loads((FIXTURE / "memory_layout_v4.json").read_text(encoding="utf-8"))
    golden = json.loads((FIXTURE / "memory_golden_v4.json").read_text(encoding="utf-8"))
    image = (FIXTURE / "parameters_v4.bin").read_bytes()

    assert len(image) == layout["image_bytes"]
    assert digest(image) == layout["image_sha256"] == golden["image_sha256"]
    assert len(layout["stages"]) == len(golden["stages"]) == 12

    stage_results = []
    for stage, reference in zip(layout["stages"], golden["stages"], strict=True):
        assert stage["id"] == reference["id"]
        begin = stage["dram_byte_offset"]
        end = begin + stage["transfer_bytes"]
        actual = digest(image[begin:end])
        assert actual == reference["stage_sha256"]
        stage_results.append(
            {
                "id": stage["id"],
                "transfer_bytes": stage["transfer_bytes"],
                "stage_sha256": actual,
            }
        )

    lut = layout["global_sigmoid_lut"]
    begin = lut["dram_byte_offset"]
    actual_lut_sha = digest(image[begin : begin + lut["payload_bytes"]])
    assert actual_lut_sha == lut["sha256"] == golden["global_sigmoid_lut"]["sha256"]

    dense_bytes = sum(item["transfer_bytes"] for item in layout["stages"])
    assert dense_bytes == 1_050_544
    assert lut["transfer_bytes"] == 2_040
    return {
        "baseline": "sequential-v4-dense-import",
        "result": "PASS",
        "image_bytes": len(image),
        "image_sha256": digest(image),
        "dense_bytes_per_frame": dense_bytes,
        "lut_bytes_per_reset_epoch": lut["transfer_bytes"],
        "stages": stage_results,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, help="optional JSON report path")
    args = parser.parse_args()
    report = reproduce()
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.report:
        target = args.report.resolve()
        target.relative_to(ROOT.resolve())
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(encoded, encoding="utf-8")
    print(
        "DENSE_BASELINE_PASS "
        f"stages={len(report['stages'])} bytes={report['dense_bytes_per_frame']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
