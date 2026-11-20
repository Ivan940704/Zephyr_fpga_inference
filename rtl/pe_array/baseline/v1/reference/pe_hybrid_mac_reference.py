#!/usr/bin/env python3
"""Generate deterministic stateful vectors for pe_hybrid_mac."""

from __future__ import annotations

import random
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tb" / "vectors" / "pe_hybrid_mac_vectors.txt"


def wrap32(value: int) -> int:
    value &= 0xFFFF_FFFF
    return value - (1 << 32) if value & 0x8000_0000 else value


def term(mode: int, a: int, b: int, gate: int, spike: int, direct: int) -> int:
    if mode == 0:
        return a * b
    if mode == 1:
        return b if spike else 0
    if mode == 2:
        return gate * b
    return direct


def main() -> None:
    rng = random.Random(0x5EED_16)
    requests: list[tuple[int, int, int, int, int, int, int, int]] = [
        (1, 1, 0, 127, 127, 0, 0, 0),
        (0, 1, 0, -128, 127, 0, 0, 0),
        (0, 1, 1, 0, -127, 0, 1, 0),
        (0, 1, 1, 0, 99, 0, 0, 0),
        (0, 1, 2, 0, -128, 255, 0, 0),
        (0, 1, 2, 0, 127, 0, 0, 0),
        (0, 1, 3, 0, 0, 0, 0, 2_147_483_647),
        (0, 1, 3, 0, 0, 0, 0, 1),
        (1, 1, 3, 0, 0, 0, 0, -2_147_483_648),
        (0, 1, 3, 0, 0, 0, 0, -2_147_483_648),
        (0, 1, 3, 0, 0, 0, 0, -1),
        (1, 0, 0, 0, 0, 0, 0, 0),
    ]

    for index in range(4096):
        clear = 1 if index % 257 == 0 else 0
        enable = 0 if index % 19 == 0 else 1
        mode = rng.randrange(4)
        a = rng.randrange(-128, 128)
        b = rng.randrange(-128, 128)
        gate = rng.randrange(256)
        spike = rng.randrange(2)
        direct = rng.randrange(-1_000_000, 1_000_001)
        requests.append((clear, enable, mode, a, b, gate, spike, direct))

    # Drain the one-entry command pipeline so the final random request is seen.
    requests.append((0, 0, 0, 0, 0, 0, 0, 0))

    accumulator = 0
    overflow = 0
    pending_term: int | None = None
    lines = ["# clear enable mode a b gate spike direct expected_acc expected_overflow"]
    for clear, enable, mode, a, b, gate, spike, direct in requests:
        if clear:
            accumulator = 0
            overflow = 0
            pending_term = None
        else:
            if pending_term is not None:
                raw = accumulator + pending_term
                if raw < -(1 << 31) or raw > (1 << 31) - 1:
                    overflow = 1
                accumulator = wrap32(raw)
            pending_term = term(mode, a, b, gate, spike, direct) if enable else None
        lines.append(
            f"{clear} {enable} {mode} {a} {b} {gate} {spike} {direct} "
            f"{accumulator} {overflow}"
        )

    OUTPUT.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"PE_HYBRID_REFERENCE vectors={len(requests)} output={OUTPUT}")


if __name__ == "__main__":
    main()
