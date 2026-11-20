#!/usr/bin/env python3
"""Standalone bit-exact reference and vector generator for pe_requant_lane.

The arithmetic is a direct scalar transcription of IntegerRequantizer.forward in
upstream/audiozen/models/spiking_fullsubnet/integer_ptq.py.  It intentionally has
no PyTorch or NumPy dependency.  An optional --torch-cross-check mode invokes the
actual upstream IntegerRequantizer when PyTorch is available.
"""

from __future__ import annotations

import argparse
import hashlib
import random
import sys
from dataclasses import dataclass
from pathlib import Path


INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1
INT64_MIN = -(1 << 63)
INT64_MAX = (1 << 63) - 1
MULTIPLIER_LIMIT = 1 << 30
SHIFT_MAX = 62
DEFAULT_SEED = 0x5EED_2026
DEFAULT_RANDOM_COUNT = 4096


@dataclass(frozen=True)
class Vector:
    value: int
    multiplier: int
    shift: int
    tag: int
    expected: int


def requantize(value: int, multiplier: int, shift: int) -> int:
    """Match upstream IntegerRequantizer.forward for one scalar transaction."""

    if not INT32_MIN <= value <= INT32_MAX:
        raise ValueError(f"value {value} is outside signed INT32")
    if not -MULTIPLIER_LIMIT <= multiplier <= MULTIPLIER_LIMIT:
        raise ValueError(f"multiplier {multiplier} exceeds abs(2**30)")
    if not 0 <= shift <= SHIFT_MAX:
        raise ValueError(f"shift {shift} is outside 0..{SHIFT_MAX}")

    product = value * multiplier
    rounding = 0 if shift == 0 else 1 << (shift - 1)
    rounded_magnitude = (abs(product) + rounding) >> shift
    result = -rounded_magnitude if product < 0 else rounded_magnitude

    if not INT64_MIN <= product <= INT64_MAX:
        raise AssertionError("legal input product must fit signed INT64")
    if not INT64_MIN <= result <= INT64_MAX:
        raise AssertionError("legal requant result must fit signed INT64")
    return result


def _directed_operands() -> list[tuple[int, int, int]]:
    cases: list[tuple[int, int, int]] = []
    seen: set[tuple[int, int, int]] = set()

    def add(value: int, multiplier: int, shift: int) -> None:
        key = (value, multiplier, shift)
        if key not in seen:
            requantize(*key)
            seen.add(key)
            cases.append(key)

    values = [
        0,
        1,
        -1,
        2,
        -2,
        3,
        -3,
        7,
        -7,
        127,
        -127,
        INT32_MAX,
        INT32_MIN,
    ]
    multipliers = [
        0,
        1,
        -1,
        1 << 29,
        -(1 << 29),
        MULTIPLIER_LIMIT,
        -MULTIPLIER_LIMIT,
        1_073_725_318,
        -870_368_182,
    ]
    shifts = [0, 1, 2, 20, 30, 35, SHIFT_MAX]

    for value in values:
        for multiplier in multipliers:
            for shift in shifts:
                add(value, multiplier, shift)

    # Exact half-way cases.  The expected policy is nearest with ties away
    # from zero, implemented by rounding the magnitude and restoring the sign.
    for shift in range(1, 31):
        half = 1 << (shift - 1)
        for magnitude in (half, 3 * half):
            if magnitude <= INT32_MAX:
                add(magnitude, 1, shift)
                add(-magnitude, 1, shift)
                add(magnitude, -1, shift)
                add(-magnitude, -1, shift)

    # The largest legal shift still has representable positive and negative
    # ties when INT32_MIN is multiplied by +/-2**30.
    add(INT32_MIN, MULTIPLIER_LIMIT, SHIFT_MAX)
    add(INT32_MIN, -MULTIPLIER_LIMIT, SHIFT_MAX)

    # Values immediately below and above representative half-way boundaries.
    for shift in (1, 2, 7, 20, 30):
        half = 1 << (shift - 1)
        for delta in (-1, 0, 1):
            magnitude = half + delta
            if 0 <= magnitude <= INT32_MAX:
                add(magnitude, 1, shift)
                add(-magnitude, 1, shift)

    return cases


def build_vectors(random_count: int, seed: int) -> list[Vector]:
    operands = _directed_operands()
    rng = random.Random(seed)

    for _ in range(random_count):
        value = rng.randint(INT32_MIN, INT32_MAX)
        multiplier = rng.randint(-MULTIPLIER_LIMIT, MULTIPLIER_LIMIT)
        shift = rng.randint(0, SHIFT_MAX)
        operands.append((value, multiplier, shift))

    vectors = [
        Vector(value, multiplier, shift, index & 0xFFFF, requantize(value, multiplier, shift))
        for index, (value, multiplier, shift) in enumerate(operands)
    ]
    return vectors


def run_contract_self_test() -> None:
    assert requantize(0, 0, 0) == 0
    assert requantize(7, 3, 0) == 21
    assert requantize(-7, 3, 0) == -21
    assert requantize(1, 1, 1) == 1
    assert requantize(-1, 1, 1) == -1
    assert requantize(3, 1, 1) == 2
    assert requantize(-3, 1, 1) == -2
    assert requantize(1, 1, 2) == 0
    assert requantize(-1, 1, 2) == 0
    assert requantize(INT32_MIN, MULTIPLIER_LIMIT, SHIFT_MAX) == -1
    assert requantize(INT32_MIN, -MULTIPLIER_LIMIT, SHIFT_MAX) == 1

    rng = random.Random(0x51_6E)
    for _ in range(1000):
        value = rng.randint(0, INT32_MAX)
        multiplier = rng.randint(-MULTIPLIER_LIMIT, MULTIPLIER_LIMIT)
        shift = rng.randint(0, SHIFT_MAX)
        assert requantize(-value, multiplier, shift) == -requantize(value, multiplier, shift)
        assert requantize(value, multiplier, 0) == value * multiplier


def write_vectors(path: Path, vectors: list[Vector]) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = "".join(
        f"{v.value} {v.multiplier} {v.shift} {v.tag} {v.expected}\n" for v in vectors
    )
    path.write_text(payload, encoding="ascii")
    return hashlib.sha256(payload.encode("ascii")).hexdigest()


def read_vectors(path: Path) -> list[Vector]:
    vectors: list[Vector] = []
    for line_number, line in enumerate(path.read_text(encoding="ascii").splitlines(), start=1):
        fields = line.split()
        if len(fields) != 5:
            raise ValueError(f"{path}:{line_number}: expected five integer fields")
        value, multiplier, shift, tag, expected = map(int, fields)
        actual = requantize(value, multiplier, shift)
        if actual != expected:
            raise AssertionError(
                f"{path}:{line_number}: expected {expected}, recomputed {actual}"
            )
        vectors.append(Vector(value, multiplier, shift, tag, expected))
    if not vectors:
        raise ValueError(f"{path}: no vectors")
    return vectors


def torch_cross_check(vectors: list[Vector], upstream_root: Path) -> None:
    """Invoke the actual upstream IntegerRequantizer.forward when available."""

    sys.path.insert(0, str(upstream_root))
    try:
        import torch
        from audiozen.models.spiking_fullsubnet.integer_ptq import IntegerRequantizer
    except Exception as exc:  # pragma: no cover - depends on optional environment
        raise RuntimeError("PyTorch/upstream import is unavailable") from exc

    for offset in range(0, len(vectors), 1024):
        chunk = vectors[offset : offset + 1024]
        values = torch.tensor([v.value for v in chunk], dtype=torch.int32)
        multipliers = torch.tensor([v.multiplier for v in chunk], dtype=torch.int64)
        shifts = torch.tensor([v.shift for v in chunk], dtype=torch.int64)
        requantizer = IntegerRequantizer(torch.zeros(len(chunk), dtype=torch.float64))
        requantizer.multiplier = multipliers
        requantizer.right_shift = shifts
        actual = requantizer(values).cpu().tolist()
        expected = [v.expected for v in chunk]
        if actual != expected:
            for index, (got, want) in enumerate(zip(actual, expected)):
                if got != want:
                    raise AssertionError(
                        f"upstream mismatch at vector {offset + index}: {got} != {want}"
                    )


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    default_output = script_dir.parent / "tb" / "vectors" / "pe_requant_lane_vectors.txt"
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=default_output)
    parser.add_argument("--random-count", type=int, default=DEFAULT_RANDOM_COUNT)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=DEFAULT_SEED)
    parser.add_argument("--verify", type=Path)
    parser.add_argument("--torch-cross-check", action="store_true")
    parser.add_argument("--upstream-root", type=Path, default=script_dir.parents[2] / "upstream")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_contract_self_test()

    if args.verify is not None:
        vectors = read_vectors(args.verify)
        digest = hashlib.sha256(args.verify.read_bytes()).hexdigest()
        action = "verified"
        output_path = args.verify
    else:
        if args.random_count < 0:
            raise ValueError("--random-count must be non-negative")
        vectors = build_vectors(args.random_count, args.seed)
        digest = write_vectors(args.output, vectors)
        action = "generated"
        output_path = args.output

    if args.torch_cross_check:
        torch_cross_check(vectors, args.upstream_root.resolve())

    print(
        f"PASS: {action} {len(vectors)} pe_requant_lane vectors; "
        f"sha256={digest}; path={output_path.resolve()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
