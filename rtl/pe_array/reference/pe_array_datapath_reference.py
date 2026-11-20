#!/usr/bin/env python3
"""Generate one deterministic bit-exact PE-datapath integration scenario.

The generated Verilog header is intentionally temporary test input.  It
exercises a partial sixteen-lane GSU/QBN tile and a partial eight-bin CDF
group while keeping every arithmetic expectation in this Python reference.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def round_away(value: int, shift: int) -> int:
    if shift == 0:
        return value
    magnitude = abs(value)
    rounded = (magnitude + (1 << (shift - 1))) >> shift
    return -rounded if value < 0 else rounded


def saturate_symmetric_int8(value: int) -> int:
    return max(-127, min(127, value))


def requant(value: int, multiplier: int, shift: int) -> int:
    return round_away(value * multiplier, shift)


def shared_requant(
    value: int, multiplier: int, shift: int, bias: int
) -> int:
    rq_value = requant(value, multiplier, shift)
    guarded = round_away(rq_value + bias, 8)
    return saturate_symmetric_int8(guarded)


def pack(values: list[int], width: int) -> int:
    mask = (1 << width) - 1
    result = 0
    for lane, value in enumerate(values):
        result |= (value & mask) << (lane * width)
    return result


def literal(name: str, width: int, value: int) -> str:
    digits = (width + 3) // 4
    return f"localparam [{width - 1}:0] {name} = {width}'h{value:0{digits}x};"


def load_sigmoid_table(path: Path) -> list[int]:
    values = [int(line.strip(), 16) for line in path.read_text().splitlines()
              if line.strip()]
    if len(values) != 8 * 255:
        raise ValueError(
            f"expected 2040 sigmoid bytes, found {len(values)} in {path}"
        )
    if any(value < 0 or value > 255 for value in values):
        raise ValueError("sigmoid table contains a non-byte value")
    return values


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sigmoid-table", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    table = load_sigmoid_table(args.sigmoid_table)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    # Every four-lane group is non-empty so all four gate packets are used.
    gate_mask = 0xB5D7
    gate_tags = [0x1100 + lane for lane in range(16)]
    table_select = 0

    gate_raw_i = [((lane * 7 + 3) % 31) - 15 for lane in range(16)]
    gate_i = [((lane * 11 + 5) % 37) - 18 for lane in range(16)]
    gate_i_bias = [
        (gate_i[lane] - gate_raw_i[lane]) * 256 for lane in range(16)
    ]

    gate_raw_lambda = [((lane * 5 + 1) % 25) - 12 for lane in range(16)]
    gate_lambda_q = [((lane * 9 + 4) % 29) - 14 for lane in range(16)]
    gate_lambda_bias = [
        (gate_lambda_q[lane] - gate_raw_lambda[lane]) * 256
        for lane in range(16)
    ]
    gate_lambda = [
        table[table_select * 255 + gate_lambda_q[lane] + 127]
        for lane in range(16)
    ]

    u_prev = [((lane * 13 + 9) % 61) - 30 for lane in range(16)]
    membrane_pre = []
    for lane in range(16):
        cx = gate_lambda[lane] * u_prev[lane]
        cell = (255 - gate_lambda[lane]) * gate_i[lane]
        membrane_pre.append(
            saturate_symmetric_int8(round_away(cx + cell, 8))
        )

    desired_qbn_pattern = [-9, -1, 0, 1, 11, -4, 0, -7]
    qbn_expected = [desired_qbn_pattern[lane % len(desired_qbn_pattern)]
                    for lane in range(16)]
    qbn_multiplier = [256] * 16
    qbn_shift = [0] * 16
    qbn_bias = [
        (qbn_expected[lane] - membrane_pre[lane]) * 256
        for lane in range(16)
    ]
    assert all(
        shared_requant(
            membrane_pre[lane], qbn_multiplier[lane],
            qbn_shift[lane], qbn_bias[lane]
        ) == qbn_expected[lane]
        for lane in range(16)
    )

    # One Linear tile provides Cr in lanes 0..7 and Ci in lanes 8..15.
    cdf_mask = 0xB7
    linear_mask = cdf_mask | (cdf_mask << 8)
    linear_tags = [0x2200 + lane for lane in range(16)]
    coefficient_real = [7, -5, 3, 11, -9, 4, -2, 6]
    coefficient_imag = [-3, 8, -7, 2, 5, -11, 9, -4]
    linear_expected = coefficient_real + coefficient_imag
    linear_raw = [
        ((lane * 9 + 2) % 31) - 15 for lane in range(16)
    ]
    linear_multiplier = [256] * 16
    linear_shift = [0] * 16
    linear_bias = [
        (linear_expected[lane] - linear_raw[lane]) * 256
        for lane in range(16)
    ]
    assert all(
        shared_requant(
            linear_raw[lane], linear_multiplier[lane],
            linear_shift[lane], linear_bias[lane]
        ) == linear_expected[lane]
        for lane in range(16)
    )

    spectrum_real = [12, -7, 0, 15, -11, 6, -4, 9]
    spectrum_imag = [-5, 13, 8, -2, 7, -9, 3, 10]
    cdf_real = [0] * 8
    cdf_imag = [0] * 8
    for lane in range(8):
        if cdf_mask & (1 << lane):
            cdf_real[lane] = (
                spectrum_real[lane] * coefficient_real[lane]
                - spectrum_imag[lane] * coefficient_imag[lane]
            )
            cdf_imag[lane] = (
                spectrum_real[lane] * coefficient_imag[lane]
                + spectrum_imag[lane] * coefficient_real[lane]
            )

    highest_gate_lane = max(
        lane for lane in range(16) if gate_mask & (1 << lane)
    )
    qbn_events = [
        lane for lane in range(16)
        if gate_mask & (1 << lane)
        and (qbn_expected[lane] >= 0 or lane == highest_gate_lane)
    ]

    constants = [
        literal("SC_GATE_MASK", 16, gate_mask),
        literal("SC_GATE_TAGS", 256, pack(gate_tags, 16)),
        literal("SC_GATE_TABLE_SELECT", 3, table_select),
        literal("SC_GATE_RAW_I", 128, pack(gate_raw_i, 8)),
        literal("SC_GATE_I_BIAS", 512, pack(gate_i_bias, 32)),
        literal("SC_GATE_EXPECT_I", 128, pack(gate_i, 8)),
        literal("SC_GATE_RAW_LAMBDA", 128, pack(gate_raw_lambda, 8)),
        literal("SC_GATE_LAMBDA_BIAS", 512, pack(gate_lambda_bias, 32)),
        literal("SC_GATE_EXPECT_LAMBDA_Q", 128, pack(gate_lambda_q, 8)),
        literal("SC_GATE_EXPECT_LAMBDA", 128, pack(gate_lambda, 8)),
        literal("SC_MEMBRANE_U_PREV", 128, pack(u_prev, 8)),
        literal("SC_MEMBRANE_EXPECT_PRE", 128, pack(membrane_pre, 8)),
        literal("SC_QBN_MULTIPLIER", 512, pack(qbn_multiplier, 32)),
        literal("SC_QBN_SHIFT", 96, pack(qbn_shift, 6)),
        literal("SC_QBN_BIAS", 512, pack(qbn_bias, 32)),
        literal("SC_QBN_EXPECT", 128, pack(qbn_expected, 8)),
        literal("SC_QBN_BASE", 9, 32),
        literal("SC_LINEAR_MASK", 16, linear_mask),
        literal("SC_LINEAR_TAGS", 256, pack(linear_tags, 16)),
        literal("SC_LINEAR_RAW", 128, pack(linear_raw, 8)),
        literal("SC_LINEAR_MULTIPLIER", 512, pack(linear_multiplier, 32)),
        literal("SC_LINEAR_SHIFT", 96, pack(linear_shift, 6)),
        literal("SC_LINEAR_BIAS", 512, pack(linear_bias, 32)),
        literal("SC_LINEAR_EXPECT", 128, pack(linear_expected, 8)),
        literal("SC_LINEAR_BASE", 9, 128),
        literal("SC_CDF_MASK", 8, cdf_mask),
        literal("SC_CDF_SPECTRUM_REAL", 64, pack(spectrum_real, 8)),
        literal("SC_CDF_SPECTRUM_IMAG", 64, pack(spectrum_imag, 8)),
        literal("SC_CDF_EXPECT_REAL", 256, pack(cdf_real, 32)),
        literal("SC_CDF_EXPECT_IMAG", 256, pack(cdf_imag, 32)),
        literal("SC_CDF_BASE", 8, 64),
        literal("SC_CDF_BAND", 2, 2),
        literal("SC_CDF_TAG", 16, 0x3301),
    ]

    header = "\n".join([
        "`ifndef PE_ARRAY_DATAPATH_VECTORS_VH",
        "`define PE_ARRAY_DATAPATH_VECTORS_VH",
        *constants,
        "`endif",
        "",
    ])
    (args.output_dir / "pe_array_datapath_vectors.vh").write_text(
        header, encoding="ascii"
    )

    summary = {
        "status": "PASS",
        "gate_mask": f"0x{gate_mask:04x}",
        "gate_active_lanes": gate_mask.bit_count(),
        "qbn_state_writes": gate_mask.bit_count(),
        "qbn_active_events": len(qbn_events),
        "qbn_spikes": sum(
            1 for lane in range(16)
            if gate_mask & (1 << lane) and qbn_expected[lane] >= 0
        ),
        "qbn_terminal_lane": highest_gate_lane,
        "linear_coefficients": linear_mask.bit_count(),
        "cdf_order": 1,
        "cdf_active_bins": cdf_mask.bit_count(),
        "cdf_max_abs": max(
            max(abs(value) for value in cdf_real),
            max(abs(value) for value in cdf_imag),
        ),
        "sigmoid_table": str(args.sigmoid_table.resolve()),
        "rounding": "nearest, ties away from zero",
    }
    (args.output_dir / "pe_array_datapath_reference_summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print("PE_ARRAY_DATAPATH_REFERENCE_PASS", json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
