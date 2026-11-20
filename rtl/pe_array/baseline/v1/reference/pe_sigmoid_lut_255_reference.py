#!/usr/bin/env python3
"""Verify and export all eight real sigmoid tables for pe_sigmoid_lut_255."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


PE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REPO = PE_ROOT.parents[1]
DEFAULT_OUTPUT = PE_ROOT / "tb" / "vectors" / "pe_sigmoid_lut_255_tables.hex"
DEFAULT_SUMMARY = PE_ROOT / "reports" / "pe_sigmoid_lut_255" / "reference_summary.json"


def sigmoid(value: float) -> float:
    if value >= 0.0:
        inverse = math.exp(-value)
        return 1.0 / (1.0 + inverse)
    exponential = math.exp(value)
    return exponential / (1.0 + exponential)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--upstream-root",
        type=Path,
        default=DEFAULT_REPO / "upstream",
        help="Path containing parameters/manifest.json and parameters.bin",
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--summary", type=Path, default=DEFAULT_SUMMARY)
    args = parser.parse_args()

    parameter_root = args.upstream_root.resolve() / "parameters"
    manifest_path = parameter_root / "manifest.json"
    report_path = parameter_root / "integer_reference_report.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    report = json.loads(report_path.read_text(encoding="utf-8"))
    blob_path = parameter_root / manifest["storage"]["file"]
    blob = blob_path.read_bytes()

    if manifest["quantization"]["gate_denominator"] != 255:
        raise AssertionError("pe_sigmoid_lut_255 requires gate_denominator == 255")

    operator_names = sorted(
        name
        for name, metadata in manifest["operators"].items()
        if "sigmoid_lut" in metadata.get("tensors", {})
    )
    if len(operator_names) != 8:
        raise AssertionError(f"expected 8 sigmoid tables, found {len(operator_names)}")

    all_values: list[int] = []
    table_summaries: list[dict[str, object]] = []
    table_hashes: set[str] = set()

    for table_index, operator_name in enumerate(operator_names):
        entry = manifest["operators"][operator_name]["tensors"]["sigmoid_lut"]
        if entry["dtype"] != "uint8" or entry["shape"] != [255] or entry["nbytes"] != 255:
            raise AssertionError(f"unexpected LUT metadata for {operator_name}: {entry}")

        start = int(entry["offset"])
        payload = blob[start : start + int(entry["nbytes"])]
        digest = hashlib.sha256(payload).hexdigest()
        if digest != entry["sha256"]:
            raise AssertionError(f"SHA-256 mismatch for {operator_name}")

        values = list(payload)
        scale = float(report["operators"][operator_name]["forget_pre_scale"])
        regenerated = [
            max(0, min(255, round(sigmoid(gate_q * scale) * 255.0)))
            for gate_q in range(-127, 128)
        ]
        if regenerated != values:
            mismatch = next(
                index for index, (actual, expected) in enumerate(zip(values, regenerated))
                if actual != expected
            )
            raise AssertionError(
                f"formula mismatch table={table_index} operator={operator_name} "
                f"gate={mismatch - 127} blob={values[mismatch]} formula={regenerated[mismatch]}"
            )
        if values[0] != 0 or values[127] != 128 or values[254] != 255:
            raise AssertionError(f"endpoint mismatch for {operator_name}")
        if any(left > right for left, right in zip(values, values[1:])):
            raise AssertionError(f"non-monotonic table for {operator_name}")

        table_hashes.add(digest)
        all_values.extend(values)
        table_summaries.append(
            {
                "table_index": table_index,
                "operator": operator_name,
                "forget_pre_scale": scale,
                "sha256": digest,
                "first": values[0],
                "mid": values[127],
                "last": values[254],
            }
        )

    if len(table_hashes) != 8:
        raise AssertionError("the eight resident tables must be distinct")
    if len(all_values) != 8 * 255:
        raise AssertionError("unexpected flattened LUT length")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(f"{value:02x}" for value in all_values) + "\n", encoding="ascii")

    summary = {
        "gate_denominator": 255,
        "input_qmin": -127,
        "input_qmax": 127,
        "output_dtype": "uint8",
        "output_scale": "1/255",
        "table_count": 8,
        "entries_per_table": 255,
        "total_entries": len(all_values),
        "unique_table_hashes": len(table_hashes),
        "parameter_blob": str(blob_path),
        "parameter_blob_sha256": hashlib.sha256(blob).hexdigest(),
        "manifest": str(manifest_path),
        "tables": table_summaries,
    }
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.summary.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(
        "PE_SIGMOID_REFERENCE "
        f"tables={len(operator_names)} entries_per_table=255 total_entries={len(all_values)} "
        f"unique={len(table_hashes)} endpoints=0_128_255"
    )


if __name__ == "__main__":
    main()
