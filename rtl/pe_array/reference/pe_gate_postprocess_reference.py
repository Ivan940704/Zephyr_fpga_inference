#!/usr/bin/env python3
"""Bit-exact reference and vector generator for pe_gate_postprocess."""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import struct
from pathlib import Path


PE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
UPSTREAM_ROOT = REPO_ROOT / "upstream"
MANIFEST_PATH = UPSTREAM_ROOT / "parameters" / "manifest.json"
PARAMETER_PATH = UPSTREAM_ROOT / "parameters" / "parameters.bin"
VECTOR_PATH = PE_ROOT / "tb" / "vectors" / "pe_gate_postprocess_vectors.hex"
COUNT_PATH = PE_ROOT / "tb" / "vectors" / "pe_gate_postprocess_vectors.count"
SUMMARY_PATH = PE_ROOT / "reports" / "pe_gate_postprocess" / "reference_summary.json"

LANES = 4
TAG_WIDTH = 16
VECTOR_WIDTH = 741
GUARD_BITS = 8
INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1


def signed_round_shift(value: int, bits: int) -> int:
    if bits == 0:
        return value
    magnitude = (abs(value) + (1 << (bits - 1))) >> bits
    return -magnitude if value < 0 else magnitude


def requant(value: int, multiplier: int, shift: int) -> int:
    return signed_round_shift(value * multiplier, shift)


def postprocess(input_rq: int, recurrent_rq: int, bias: int) -> tuple[int, int]:
    guarded_sum = input_rq + recurrent_rq + bias
    unclamped = signed_round_shift(guarded_sum, GUARD_BITS)
    return max(-127, min(127, unclamped)), unclamped


def twos(value: int, width: int) -> int:
    return value & ((1 << width) - 1)


def pack_fields(fields: list[tuple[int, int]]) -> int:
    word = 0
    offset = 0
    for value, width in fields:
        word |= twos(value, width) << offset
        offset += width
    if offset != VECTOR_WIDTH:
        raise AssertionError(f"packed width {offset} != {VECTOR_WIDTH}")
    return word


def make_case(
    gate: int,
    mask: int,
    biases: list[int],
    input_rq: list[int],
    recurrent_rq: list[int],
    tags: list[int],
    category: str,
) -> dict:
    expected = []
    unclamped = []
    guarded_sums = []
    for lane in range(LANES):
        value, raw = postprocess(input_rq[lane], recurrent_rq[lane], biases[lane])
        expected.append(value)
        unclamped.append(raw)
        guarded_sums.append(input_rq[lane] + recurrent_rq[lane] + biases[lane])
    fields = [(gate, 1), (mask, 4)]
    fields.extend((value, 32) for value in biases)
    fields.extend((value, 64) for value in input_rq)
    fields.extend((value, 64) for value in recurrent_rq)
    fields.extend((value, TAG_WIDTH) for value in tags)
    fields.extend((value, 8) for value in expected)
    return {
        "word": pack_fields(fields),
        "gate": gate,
        "mask": mask,
        "expected": expected,
        "unclamped": unclamped,
        "guarded_sums": guarded_sums,
        "category": category,
    }


def tensor_values(manifest: dict, blob: bytes, operator: str, name: str) -> list[int]:
    entry = manifest["operators"][operator]["tensors"][name]
    formats = {"int8": "b", "uint8": "B", "int32": "i", "int64": "q"}
    item_format = formats[entry["dtype"]]
    item_size = struct.calcsize(item_format)
    raw = blob[entry["offset"] : entry["offset"] + entry["nbytes"]]
    return list(struct.unpack("<" + item_format * (len(raw) // item_size), raw))


def build_vectors() -> tuple[list[dict], dict]:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    blob = PARAMETER_PATH.read_bytes()
    rng = random.Random(0x47505450)
    cases: list[dict] = []
    real_packets = 0
    real_gate_values = 0

    operators = sorted(
        name
        for name, operator in manifest["operators"].items()
        if operator["class"] == "IntegerGSUCellReference"
    )
    if len(operators) != 8:
        raise AssertionError(f"expected 8 integer GSU cells, found {len(operators)}")

    accumulator_edges = [
        INT32_MIN,
        INT32_MAX,
        -1_000_000,
        1_000_000,
        -1,
        0,
        1,
    ]

    for operator_index, operator in enumerate(operators):
        biases = tensor_values(manifest, blob, operator, "bias_q")
        input_multiplier = tensor_values(
            manifest, blob, operator, "input_requantizer.multiplier"
        )
        input_shift = tensor_values(
            manifest, blob, operator, "input_requantizer.right_shift"
        )
        recurrent_multiplier = tensor_values(
            manifest, blob, operator, "recurrent_requantizer.multiplier"
        )
        recurrent_shift = tensor_values(
            manifest, blob, operator, "recurrent_requantizer.right_shift"
        )
        hidden_size = len(biases) // 2
        if hidden_size not in {224, 320} or len(biases) != 2 * hidden_size:
            raise AssertionError(f"unexpected gate shape for {operator}: {len(biases)}")

        for gate in range(2):
            for base in range(0, hidden_size, LANES):
                lane_bias = []
                lane_input_rq = []
                lane_recurrent_rq = []
                lane_tag = []
                for lane in range(LANES):
                    channel = base + lane
                    parameter_index = gate * hidden_size + channel
                    selector = (operator_index * 17 + gate * 11 + channel) % len(
                        accumulator_edges
                    )
                    if channel % 9 == 0:
                        input_acc = accumulator_edges[selector]
                    else:
                        input_acc = rng.randint(INT32_MIN, INT32_MAX)
                    if channel % 7 == 0:
                        recurrent_acc = accumulator_edges[-selector - 1]
                    else:
                        recurrent_acc = rng.randint(INT32_MIN, INT32_MAX)
                    lane_bias.append(biases[parameter_index])
                    lane_input_rq.append(
                        requant(
                            input_acc,
                            input_multiplier[parameter_index],
                            input_shift[parameter_index],
                        )
                    )
                    lane_recurrent_rq.append(
                        requant(
                            recurrent_acc,
                            recurrent_multiplier[parameter_index],
                            recurrent_shift[parameter_index],
                        )
                    )
                    lane_tag.append((operator_index << 10) | (gate << 9) | channel)
                cases.append(
                    make_case(
                        gate,
                        0xF,
                        lane_bias,
                        lane_input_rq,
                        lane_recurrent_rq,
                        lane_tag,
                        "real",
                    )
                )
                real_packets += 1
                real_gate_values += LANES

    boundary_sums = [
        -32641,
        -32640,
        -32639,
        -32384,
        -129,
        -128,
        -127,
        -1,
        0,
        1,
        127,
        128,
        129,
        32383,
        32384,
        32639,
        32640,
        32641,
    ]
    directed_packets = 0
    for mask in range(16):
        lane_bias = []
        lane_input_rq = []
        lane_recurrent_rq = []
        lane_tag = []
        for lane in range(LANES):
            target_sum = boundary_sums[(mask * LANES + lane) % len(boundary_sums)]
            bias = [-15933, 8761, -128, 127][lane]
            recurrent = (mask * 7919 - lane * 12347) * (-1 if lane & 1 else 1)
            lane_bias.append(bias)
            lane_recurrent_rq.append(recurrent)
            lane_input_rq.append(target_sum - recurrent - bias)
            lane_tag.append(0xD000 | (mask << 4) | lane)
        cases.append(
            make_case(
                mask & 1,
                mask,
                lane_bias,
                lane_input_rq,
                lane_recurrent_rq,
                lane_tag,
                "directed",
            )
        )
        directed_packets += 1

    random_packets = 512
    for packet in range(random_packets):
        mask = rng.randrange(16)
        gate = rng.randrange(2)
        lane_bias = [rng.randint(INT32_MIN, INT32_MAX) for _ in range(LANES)]
        lane_input_rq = [
            rng.randint(-130_000_000_000, 130_000_000_000) for _ in range(LANES)
        ]
        lane_recurrent_rq = [
            rng.randint(-130_000_000_000, 130_000_000_000) for _ in range(LANES)
        ]
        lane_tag = [
            0x8000 | ((packet * LANES + lane) & 0x7FFF) for lane in range(LANES)
        ]
        cases.append(
            make_case(
                gate,
                mask,
                lane_bias,
                lane_input_rq,
                lane_recurrent_rq,
                lane_tag,
                "random",
            )
        )

    active_results = sum(
        sum((case["mask"] >> lane) & 1 for lane in range(LANES)) for case in cases
    )
    clipped_results = sum(
        int(((case["mask"] >> lane) & 1) and abs(case["unclamped"][lane]) > 127)
        for case in cases
        for lane in range(LANES)
    )
    active_sums = [
        case["guarded_sums"][lane]
        for case in cases
        for lane in range(LANES)
        if (case["mask"] >> lane) & 1
    ]
    summary = {
        "operators": len(operators),
        "real_packets": real_packets,
        "real_gate_values": real_gate_values,
        "directed_packets": directed_packets,
        "random_packets": random_packets,
        "total_output_packets": len(cases),
        "total_input_packets": 2 * len(cases),
        "active_results": active_results,
        "clipped_active_results": clipped_results,
        "guard_bits": GUARD_BITS,
        "guarded_sum_min": min(active_sums),
        "guarded_sum_max": max(active_sums),
        "parameter_blob_sha256": hashlib.sha256(blob).hexdigest(),
    }
    return cases, summary


def write_vectors(cases: list[dict], summary: dict) -> None:
    digits = (VECTOR_WIDTH + 3) // 4
    payload = "\n".join(f"{case['word']:0{digits}x}" for case in cases) + "\n"
    VECTOR_PATH.parent.mkdir(parents=True, exist_ok=True)
    SUMMARY_PATH.parent.mkdir(parents=True, exist_ok=True)
    VECTOR_PATH.write_text(payload, encoding="ascii")
    COUNT_PATH.write_text(f"{len(cases)}\n", encoding="ascii")
    summary = dict(summary)
    summary["vector_width_bits"] = VECTOR_WIDTH
    summary["vector_sha256"] = hashlib.sha256(payload.encode("ascii")).hexdigest()
    SUMMARY_PATH.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


def verify_vectors(cases: list[dict], summary: dict) -> None:
    words = [int(line, 16) for line in VECTOR_PATH.read_text(encoding="ascii").splitlines()]
    expected = [case["word"] for case in cases]
    if words != expected:
        mismatch = next(
            (index for index, pair in enumerate(zip(words, expected)) if pair[0] != pair[1]),
            min(len(words), len(expected)),
        )
        raise AssertionError(f"vector mismatch at index {mismatch}")
    count = int(COUNT_PATH.read_text(encoding="ascii").strip())
    if count != len(expected):
        raise AssertionError(f"count file {count} != {len(expected)}")
    stored_summary = json.loads(SUMMARY_PATH.read_text(encoding="utf-8"))
    for key, value in summary.items():
        if stored_summary.get(key) != value:
            raise AssertionError(f"summary mismatch for {key}")
    print(
        "PE_GATE_POSTPROCESS_REFERENCE"
        f" operators={summary['operators']}"
        f" real_gate_values={summary['real_gate_values']}"
        f" packets={summary['total_output_packets']}"
        f" active_results={summary['active_results']}"
        f" clipped={summary['clipped_active_results']}"
        " PASS"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    cases, summary = build_vectors()
    if args.write:
        write_vectors(cases, summary)
    if args.verify:
        verify_vectors(cases, summary)
    if not args.write and not args.verify:
        print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
