#!/usr/bin/env python3
"""Standalone vector generator for pe_local_requant_bank_4lane.

Each active slot uses the scalar bit-exact requantize() contract already frozen
for pe_requant_lane.  Inactive physical slots are arithmetic zero transactions,
matching the RTL's synchronized four-lane packet contract.
"""

from __future__ import annotations

import argparse
import hashlib
import random
from dataclasses import dataclass
from pathlib import Path

from pe_requant_lane_reference import (
    INT32_MAX,
    INT32_MIN,
    MULTIPLIER_LIMIT,
    SHIFT_MAX,
    requantize,
    run_contract_self_test,
)


LANE_COUNT = 4
DEFAULT_RANDOM_COUNT = 2048
DEFAULT_SEED = 0x4BA9_2026


@dataclass(frozen=True)
class Lane:
    value: int
    multiplier: int
    shift: int
    tag: int
    expected: int


@dataclass(frozen=True)
class Packet:
    mask: int
    lanes: tuple[Lane, Lane, Lane, Lane]


def _make_packet(
    index: int,
    mask: int,
    operands: list[tuple[int, int, int]],
) -> Packet:
    if not 0 <= mask < (1 << LANE_COUNT):
        raise ValueError(f"mask {mask} does not fit four lanes")
    if len(operands) != LANE_COUNT:
        raise ValueError("each bank packet must contain exactly four operands")

    lanes: list[Lane] = []
    for lane, (value, multiplier, shift) in enumerate(operands):
        tag = (index * LANE_COUNT + lane) & 0xFFFF
        if (mask >> lane) & 1:
            expected = requantize(value, multiplier, shift)
        else:
            # The wrapper forces inactive physical lane operands to zero.
            expected = 0
        lanes.append(Lane(value, multiplier, shift, tag, expected))
    return Packet(mask, tuple(lanes))  # type: ignore[arg-type]


def build_packets(random_count: int, seed: int) -> list[Packet]:
    if random_count < 0:
        raise ValueError("--random-count must be non-negative")

    directed_operands = [
        (0, 0, 0),
        (1, 1, 1),
        (-1, 1, 1),
        (3, 1, 1),
        (-3, 1, 1),
        (INT32_MAX, MULTIPLIER_LIMIT, 0),
        (INT32_MIN, MULTIPLIER_LIMIT, SHIFT_MAX),
        (INT32_MIN, -MULTIPLIER_LIMIT, SHIFT_MAX),
        (127, -870_368_182, 30),
        (-127, 1_073_725_318, 35),
        (1 << 29, 1, 30),
        (-(1 << 29), 1, 30),
    ]
    masks = [0xF, 0x1, 0x2, 0x4, 0x8, 0x5, 0xA, 0x3, 0xC, 0x0]

    packets: list[Packet] = []
    for packet_index in range(64):
        operands = [
            directed_operands[(packet_index + lane * 3) % len(directed_operands)]
            for lane in range(LANE_COUNT)
        ]
        packets.append(
            _make_packet(packet_index, masks[packet_index % len(masks)], operands)
        )

    rng = random.Random(seed)
    for _ in range(random_count):
        packet_index = len(packets)
        mask = rng.randrange(1 << LANE_COUNT)
        operands = [
            (
                rng.randint(INT32_MIN, INT32_MAX),
                rng.randint(-MULTIPLIER_LIMIT, MULTIPLIER_LIMIT),
                rng.randint(0, SHIFT_MAX),
            )
            for _lane in range(LANE_COUNT)
        ]
        packets.append(_make_packet(packet_index, mask, operands))

    return packets


def write_packets(path: Path, packets: list[Packet]) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    for packet in packets:
        fields = [str(packet.mask)]
        for lane in packet.lanes:
            fields.extend(
                str(value)
                for value in (
                    lane.value,
                    lane.multiplier,
                    lane.shift,
                    lane.tag,
                    lane.expected,
                )
            )
        lines.append(" ".join(fields))
    payload = "\n".join(lines) + "\n"
    path.write_text(payload, encoding="ascii")
    return hashlib.sha256(payload.encode("ascii")).hexdigest()


def read_packets(path: Path) -> list[Packet]:
    packets: list[Packet] = []
    for line_number, line in enumerate(
        path.read_text(encoding="ascii").splitlines(), start=1
    ):
        fields = [int(field) for field in line.split()]
        if len(fields) != 1 + 5 * LANE_COUNT:
            raise ValueError(
                f"{path}:{line_number}: expected {1 + 5 * LANE_COUNT} integer fields"
            )
        mask = fields[0]
        lanes: list[Lane] = []
        for lane_index in range(LANE_COUNT):
            base = 1 + lane_index * 5
            value, multiplier, shift, tag, expected = fields[base : base + 5]
            actual = (
                requantize(value, multiplier, shift)
                if ((mask >> lane_index) & 1)
                else 0
            )
            if actual != expected:
                raise AssertionError(
                    f"{path}:{line_number}: lane {lane_index}: "
                    f"expected {expected}, recomputed {actual}"
                )
            lanes.append(Lane(value, multiplier, shift, tag, expected))
        packets.append(Packet(mask, tuple(lanes)))  # type: ignore[arg-type]

    if not packets:
        raise ValueError(f"{path}: no packets")
    return packets


def run_bank_self_test() -> None:
    run_contract_self_test()
    packet = _make_packet(
        0,
        0b0101,
        [(3, 1, 1), (123, 456, 7), (-3, 1, 1), (-99, -88, 0)],
    )
    assert packet.lanes[0].expected == 2
    assert packet.lanes[1].expected == 0
    assert packet.lanes[2].expected == -2
    assert packet.lanes[3].expected == 0


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    default_output = (
        script_dir.parent
        / "tb"
        / "vectors"
        / "pe_local_requant_bank_4lane_vectors.txt"
    )
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=default_output)
    parser.add_argument("--random-count", type=int, default=DEFAULT_RANDOM_COUNT)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=DEFAULT_SEED)
    parser.add_argument("--verify", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_bank_self_test()

    if args.verify is not None:
        packets = read_packets(args.verify)
        digest = hashlib.sha256(args.verify.read_bytes()).hexdigest()
        action = "verified"
        output_path = args.verify
    else:
        packets = build_packets(args.random_count, args.seed)
        digest = write_packets(args.output, packets)
        action = "generated"
        output_path = args.output

    active_results = sum(packet.mask.bit_count() for packet in packets)
    print(
        f"PASS: {action} {len(packets)} bank packets / "
        f"{active_results} active lane results; sha256={digest}; "
        f"path={output_path.resolve()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
