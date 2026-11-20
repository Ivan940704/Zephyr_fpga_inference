#!/usr/bin/env python3
"""Audit the real parameter blob and selected-column sparse weight reads.

The checks are dependency-free and intentionally operate on the existing
``upstream/parameters`` files read-only.  They prove byte addressing and integer
accumulation; they do not measure AXI/DDR latency or PYNQ-Z1 performance.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import unittest
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "upstream" / "parameters" / "manifest.json"
DEFAULT_REPORT_PATH = (
    ROOT / "outputs" / "memory" / "2026-09-01" / "sparse_parameter_read_report.json"
)
LANES = 16

DTYPE_BYTES = {
    "float32": 4,
    "float64": 8,
    "int8": 1,
    "int32": 4,
    "int64": 8,
    "uint8": 1,
}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def element_count(shape: list[int]) -> int:
    return math.prod(shape) if shape else 1


def signed_int8(value: int) -> int:
    return value if value < 128 else value - 256


def tensor_records(manifest: dict) -> Iterable[tuple[str, str, dict]]:
    for operator_name, operator in manifest["operators"].items():
        for tensor_name, tensor in operator["tensors"].items():
            yield operator_name, tensor_name, tensor
    for tensor_name, tensor in manifest["unlowered_parameters"].items():
        yield "unlowered_parameters", tensor_name, tensor


def is_second_gsu_layer(operator_name: str) -> bool:
    return ".sequence_model.layers.1.cell" in operator_name


@dataclass(frozen=True)
class MatrixView:
    operator_name: str
    operator_class: str
    tensor_name: str
    offset: int
    source_rows: int
    rows: int
    columns: int
    shared_gate_halves: bool
    runtime_sparse_eligible: bool
    runtime_reason: str
    payload: bytes

    @property
    def row_tiles(self) -> int:
        return (self.rows + LANES - 1) // LANES

    @property
    def dense_words(self) -> int:
        return self.columns * self.row_tiles

    def weight(self, row: int, column: int) -> int:
        if not 0 <= row < self.rows or not 0 <= column < self.columns:
            raise IndexError((row, column))
        return signed_int8(self.payload[row * self.columns + column])

    def raw_lane_offsets(self, source_index: int, row_tile: int) -> list[int]:
        first_row = row_tile * LANES
        valid_lanes = min(LANES, self.rows - first_row)
        return [
            self.offset + (first_row + lane) * self.columns + source_index
            for lane in range(valid_lanes)
        ]

    def packed_word(self, source_index: int, row_tile: int) -> bytes:
        first_row = row_tile * LANES
        values = []
        for lane in range(LANES):
            row = first_row + lane
            values.append(
                self.payload[row * self.columns + source_index]
                if row < self.rows
                else 0
            )
        return bytes(values)

    def source_major_packed_payload(self) -> bytes:
        return b"".join(
            self.packed_word(source_index, row_tile)
            for source_index in range(self.columns)
            for row_tile in range(self.row_tiles)
        )


def load_inputs() -> tuple[dict, bytes]:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    blob_path = MANIFEST_PATH.parent / manifest["storage"]["file"]
    return manifest, blob_path.read_bytes()


def matrix_views(manifest: dict, blob: bytes) -> list[MatrixView]:
    matrices = []
    for operator_name, operator in manifest["operators"].items():
        operator_class = operator["class"]
        for tensor_name, tensor in operator["tensors"].items():
            if tensor_name not in {"weight_q", "weight_ih_q", "weight_hh_q"}:
                continue
            if tensor["dtype"] != "int8" or len(tensor["shape"]) != 2:
                raise AssertionError(f"unexpected weight tensor: {operator_name}.{tensor_name}")

            source_rows, columns = tensor["shape"]
            shared = operator_class == "IntegerGSUCellReference"
            rows = source_rows // 2 if shared else source_rows
            start = tensor["offset"]
            payload = blob[start : start + tensor["nbytes"]]

            if tensor_name == "weight_hh_q":
                eligible = True
                reason = "recurrent input is a binary spike vector"
            elif tensor_name == "weight_q":
                eligible = True
                reason = "projection input is a binary spike vector"
            elif is_second_gsu_layer(operator_name):
                eligible = True
                reason = "second GSU input is the previous GSU binary spike vector"
            else:
                eligible = False
                reason = "first GSU input is a dense normalized INT8 feature vector"

            matrices.append(
                MatrixView(
                    operator_name=operator_name,
                    operator_class=operator_class,
                    tensor_name=tensor_name,
                    offset=start,
                    source_rows=source_rows,
                    rows=rows,
                    columns=columns,
                    shared_gate_halves=shared,
                    runtime_sparse_eligible=eligible,
                    runtime_reason=reason,
                    payload=payload,
                )
            )
    return matrices


def active_patterns(columns: int, seed: int) -> dict[str, list[int]]:
    rng = random.Random(seed)
    sparse_count = max(1, round(columns / 16))
    quarter_count = max(1, round(columns / 4))
    return {
        "zero": [],
        "edge_and_middle": sorted({0, columns // 2, columns - 1}),
        "synthetic_approx_6p25pct": sorted(rng.sample(range(columns), sparse_count)),
        "synthetic_approx_25pct": sorted(rng.sample(range(columns), quarter_count)),
        "dense": list(range(columns)),
    }


def dense_binary_reference(matrix: MatrixView, active: list[int]) -> list[int]:
    return [sum(matrix.weight(row, column) for column in active) for row in range(matrix.rows)]


def selected_packed_accumulation(matrix: MatrixView, active: list[int]) -> list[int]:
    result = [0] * matrix.rows
    for source_index in active:
        for row_tile in range(matrix.row_tiles):
            word = matrix.packed_word(source_index, row_tile)
            first_row = row_tile * LANES
            for lane, raw_value in enumerate(word):
                row = first_row + lane
                if row < matrix.rows:
                    result[row] += signed_int8(raw_value)
    return result


def validate_blob(manifest: dict, blob: bytes) -> dict:
    storage = manifest["storage"]
    assert storage["nbytes"] == len(blob)
    assert storage["sha256"] == sha256(blob)

    ranges = []
    dtype_payload_bytes: Counter[str] = Counter()
    operator_tensor_count = 0
    for owner, tensor_name, tensor in tensor_records(manifest):
        dtype = tensor["dtype"]
        assert dtype in DTYPE_BYTES
        assert tensor["endianness"] == "little"
        assert tensor["file"] == storage["file"]
        expected_bytes = element_count(tensor["shape"]) * DTYPE_BYTES[dtype]
        assert tensor["nbytes"] == expected_bytes
        start = tensor["offset"]
        end = start + tensor["nbytes"]
        assert 0 <= start < end <= len(blob)
        assert tensor["sha256"] == sha256(blob[start:end])
        ranges.append((start, end, f"{owner}.{tensor_name}"))
        dtype_payload_bytes[dtype] += tensor["nbytes"]
        if owner != "unlowered_parameters":
            operator_tensor_count += 1

    ranges.sort()
    cursor = 0
    for start, end, name in ranges:
        assert start == cursor, f"gap/overlap before {name}: cursor={cursor}, start={start}"
        cursor = end
    assert cursor == len(blob)

    return {
        "blob_bytes": len(blob),
        "blob_sha256": sha256(blob),
        "operator_count": len(manifest["operators"]),
        "operator_tensor_count": operator_tensor_count,
        "unlowered_parameter_count": len(manifest["unlowered_parameters"]),
        "unlowered_parameter_bytes": sum(
            tensor["nbytes"] for tensor in manifest["unlowered_parameters"].values()
        ),
        "tensor_count_total": len(ranges),
        "dtype_payload_bytes": dict(sorted(dtype_payload_bytes.items())),
        "ranges_are_gap_free_and_nonoverlapping": True,
        "all_tensor_sha256_verified": True,
    }


def matrix_report(matrix: MatrixView, ordinal: int) -> dict:
    if matrix.shared_gate_halves:
        half_bytes = matrix.rows * matrix.columns
        first_half = matrix.payload[:half_bytes]
        second_half = matrix.payload[half_bytes:]
        assert first_half == second_half
    else:
        first_half = matrix.payload

    packed = matrix.source_major_packed_payload()
    assert len(packed) == matrix.dense_words * LANES

    zero_weights = sum(value == 0 for value in first_half)
    patterns = []
    for pattern_name, active in active_patterns(matrix.columns, 0x5A17 + ordinal).items():
        dense_result = dense_binary_reference(matrix, active)
        sparse_result = selected_packed_accumulation(matrix, active)
        assert sparse_result == dense_result
        selected_words = len(active) * matrix.row_tiles
        patterns.append(
            {
                "name": pattern_name,
                "active_count": len(active),
                "active_density": len(active) / matrix.columns,
                "selected_128b_words": selected_words,
                "dense_128b_words": matrix.dense_words,
                "words_saved": matrix.dense_words - selected_words,
                "read_reduction": 1.0 - selected_words / matrix.dense_words,
                "result_sha256": sha256(
                    b"".join(value.to_bytes(4, "little", signed=True) for value in sparse_result)
                ),
            }
        )

    offsets = matrix.raw_lane_offsets(0, 0)
    raw_deltas = [right - left for left, right in zip(offsets, offsets[1:])]
    assert raw_deltas and set(raw_deltas) == {matrix.columns}
    assert matrix.columns != 1
    assert matrix.packed_word(0, 0) == bytes(matrix.payload[row * matrix.columns] for row in range(LANES))

    return {
        "operator": matrix.operator_name,
        "operator_class": matrix.operator_class,
        "tensor": matrix.tensor_name,
        "source_shape": [matrix.source_rows, matrix.columns],
        "effective_shape": [matrix.rows, matrix.columns],
        "source_offset": matrix.offset,
        "source_bytes": len(matrix.payload),
        "effective_weight_bytes": matrix.rows * matrix.columns,
        "shared_gate_halves_verified": matrix.shared_gate_halves,
        "runtime_sparse_eligible": matrix.runtime_sparse_eligible,
        "runtime_reason": matrix.runtime_reason,
        "row_tiles_16lane": matrix.row_tiles,
        "dense_128b_words": matrix.dense_words,
        "raw_row_major_lane_stride_bytes": matrix.columns,
        "raw_first_16lane_span_bytes": offsets[-1] - offsets[0] + 1,
        "raw_first_16lane_contiguous": False,
        "source_major_packed_bytes": len(packed),
        "source_major_packed_sha256": sha256(packed),
        "source_major_word_formula": "word_index = source_index * row_tiles + row_tile",
        "lane_order": "lane 0 in lowest-address byte; zero-pad invalid final lanes",
        "weight_zero_count": zero_weights,
        "weight_zero_fraction": zero_weights / len(first_half),
        "patterns": patterns,
    }


def build_report() -> dict:
    manifest, blob = load_inputs()
    inventory = validate_blob(manifest, blob)
    matrices = matrix_views(manifest, blob)
    matrix_reports = [matrix_report(matrix, index) for index, matrix in enumerate(matrices)]

    source_weight_bytes = sum(item["source_bytes"] for item in matrix_reports)
    effective_weight_bytes = sum(item["effective_weight_bytes"] for item in matrix_reports)
    effective_zero_count = sum(item["weight_zero_count"] for item in matrix_reports)
    sparse_eligible = [item for item in matrix_reports if item["runtime_sparse_eligible"]]
    eligible_pattern_totals = {}
    for pattern_name in (
        "zero",
        "edge_and_middle",
        "synthetic_approx_6p25pct",
        "synthetic_approx_25pct",
        "dense",
    ):
        pattern_items = [
            next(pattern for pattern in item["patterns"] if pattern["name"] == pattern_name)
            for item in sparse_eligible
        ]
        selected_words = sum(item["selected_128b_words"] for item in pattern_items)
        dense_words = sum(item["dense_128b_words"] for item in pattern_items)
        eligible_pattern_totals[pattern_name] = {
            "selected_128b_words": selected_words,
            "dense_128b_words": dense_words,
            "selected_weight_bytes": selected_words * LANES,
            "dense_weight_bytes": dense_words * LANES,
            "read_reduction": 1.0 - selected_words / dense_words,
        }

    classes = Counter(operator["class"] for operator in manifest["operators"].values())
    return {
        "report_format_version": 1,
        "evidence_scope": (
            "Host byte-integrity and integer-reference test only; no RTL timing, "
            "AXI/DDR throughput, implementation, or board result."
        ),
        "source_manifest": str(MANIFEST_PATH.relative_to(ROOT)),
        "source_blob": str(
            (MANIFEST_PATH.parent / manifest["storage"]["file"]).relative_to(ROOT)
        ),
        "inventory": inventory,
        "operator_classes": dict(sorted(classes.items())),
        "matrix_summary": {
            "matrix_count": len(matrix_reports),
            "gsu_shared_matrix_count": sum(
                item["shared_gate_halves_verified"] for item in matrix_reports
            ),
            "runtime_sparse_eligible_matrix_count": len(sparse_eligible),
            "runtime_dense_matrix_count": len(matrix_reports) - len(sparse_eligible),
            "source_weight_bytes_including_duplicate_gsu_gate_halves": source_weight_bytes,
            "effective_weight_bytes_after_shared_gate_deduplication": effective_weight_bytes,
            "duplicate_shared_gate_weight_bytes": source_weight_bytes - effective_weight_bytes,
            "effective_weight_zero_count": effective_zero_count,
            "effective_weight_zero_fraction": effective_zero_count / effective_weight_bytes,
            "all_selected_index_tests_match_dense_reference": True,
            "current_raw_row_major_supports_contiguous_16lane_column_word": False,
            "proposed_word_bytes": LANES,
            "proposed_layout": "source_index -> row_tile -> lane",
            "eligible_matrix_one_invocation_pattern_totals": eligible_pattern_totals,
        },
        "matrices": matrix_reports,
    }


class SparseParameterReadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest, cls.blob = load_inputs()
        cls.matrices = matrix_views(cls.manifest, cls.blob)

    def test_manifest_and_blob_integrity(self) -> None:
        inventory = validate_blob(self.manifest, self.blob)
        self.assertEqual(inventory["blob_bytes"], 2_193_288)
        self.assertEqual(inventory["operator_count"], 12)
        self.assertEqual(inventory["unlowered_parameter_count"], 8)

    def test_shared_gsu_gate_halves_are_identical(self) -> None:
        shared_count = 0
        for matrix in self.matrices:
            if not matrix.shared_gate_halves:
                continue
            shared_count += 1
            half_bytes = matrix.rows * matrix.columns
            self.assertEqual(matrix.payload[:half_bytes], matrix.payload[half_bytes:])
        self.assertEqual(shared_count, 16)

    def test_real_weight_selected_reads_match_dense_binary_reference(self) -> None:
        tested_patterns = 0
        for ordinal, matrix in enumerate(self.matrices):
            for active in active_patterns(matrix.columns, 0x5A17 + ordinal).values():
                self.assertEqual(
                    selected_packed_accumulation(matrix, active),
                    dense_binary_reference(matrix, active),
                    f"{matrix.operator_name}.{matrix.tensor_name}",
                )
                tested_patterns += 1
        self.assertEqual(tested_patterns, 100)

    def test_raw_layout_is_strided_but_packed_word_is_contiguous(self) -> None:
        for matrix in self.matrices:
            raw_offsets = matrix.raw_lane_offsets(matrix.columns - 1, 0)
            self.assertEqual(
                [right - left for left, right in zip(raw_offsets, raw_offsets[1:])],
                [matrix.columns] * (len(raw_offsets) - 1),
            )
            gathered = bytes(
                matrix.payload[row * matrix.columns + matrix.columns - 1]
                for row in range(LANES)
            )
            self.assertEqual(matrix.packed_word(matrix.columns - 1, 0), gathered)
            packed = matrix.source_major_packed_payload()
            for source_index in (0, matrix.columns // 2, matrix.columns - 1):
                for row_tile in (0, matrix.row_tiles - 1):
                    word_index = source_index * matrix.row_tiles + row_tile
                    start = word_index * LANES
                    self.assertEqual(
                        packed[start : start + LANES],
                        matrix.packed_word(source_index, row_tile),
                    )

    def test_report_invariants(self) -> None:
        report = build_report()
        summary = report["matrix_summary"]
        self.assertEqual(summary["matrix_count"], 20)
        self.assertEqual(summary["runtime_sparse_eligible_matrix_count"], 16)
        self.assertFalse(summary["current_raw_row_major_supports_contiguous_16lane_column_word"])
        self.assertTrue(summary["all_selected_index_tests_match_dense_reference"])
        low_density = summary["eligible_matrix_one_invocation_pattern_totals"][
            "synthetic_approx_6p25pct"
        ]
        self.assertEqual(low_density["selected_128b_words"], 3_394)
        self.assertEqual(low_density["dense_128b_words"], 54_304)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-report", type=Path)
    args = parser.parse_args()
    if args.write_report is None:
        unittest.main(argv=[__file__], verbosity=2)
        return
    report = build_report()
    args.write_report.parent.mkdir(parents=True, exist_ok=True)
    args.write_report.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"wrote {args.write_report}")


if __name__ == "__main__":
    main()
