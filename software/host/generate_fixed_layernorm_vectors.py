#!/usr/bin/env python3
"""Generate deterministic text vectors for layernorm_engine_q12 XSim."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


from software.fixed_layernorm import (
    DEFAULT_FORMAT,
    fixed_layer_norm_q12,
    quantize_q12,
    reciprocal_scale_q20,
)


def build_vectors() -> list[dict[str, object]]:
    rng = np.random.default_rng(0x1A4E2)
    vectors = []
    specifications = (
        (2, 0.5, "two_element_symmetry"),
        (8, 0.125, "zero_variance_affine"),
        (64, 0.058943857358196586, "fullband_shape"),
        (46, 0.03978675181471457, "subband_0_shape"),
        (94, 0.030964057276568074, "subband_1_shape"),
        (158, 0.020789506867175966, "subband_2_shape"),
    )
    for length, output_scale, name in specifications:
        if length == 2:
            values = np.asarray([-1.0, 1.0])
            weights = np.ones(length)
            biases = np.zeros(length)
        elif length == 8:
            values = np.full(length, 0.25)
            weights = np.ones(length)
            biases = np.linspace(-0.5, 0.5, length)
        else:
            values = rng.uniform(-3.5, 7.5, length)
            weights = rng.uniform(0.18, 2.40, length)
            biases = rng.uniform(-0.52, 0.65, length)
        values_q = quantize_q12(values)
        weights_q = quantize_q12(weights)
        biases_q = quantize_q12(biases)
        reciprocal_q = reciprocal_scale_q20(output_scale)
        expected = fixed_layer_norm_q12(
            values_q, weights_q, biases_q, reciprocal_q
        )
        vectors.append(
            {
                "name": name,
                "length": length,
                "reciprocal_q20": reciprocal_q,
                "epsilon_q24": DEFAULT_FORMAT.epsilon_q,
                "values": values_q,
                "weights": weights_q,
                "biases": biases_q,
                "expected": expected,
            }
        )
    return vectors


def write_vectors(path: Path) -> None:
    vectors = build_vectors()
    lines = [f"{len(vectors)}"]
    for vector in vectors:
        lines.append(
            f"V {vector['length']} {vector['reciprocal_q20']} "
            f"{vector['epsilon_q24']}"
        )
        for values in zip(
            vector["values"], vector["weights"], vector["biases"],
            vector["expected"]
        ):
            lines.append("D " + " ".join(str(int(value)) for value in values))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"LAYER_NORM_VECTORS vectors={len(vectors)} path={path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    write_vectors(args.output)


if __name__ == "__main__":
    main()
