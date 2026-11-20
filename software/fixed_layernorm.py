"""Bit-exact integer contract for the shared PL LayerNorm engine.

This is intentionally separate from the floating-point PYNQ implementation.
It defines every rounding and saturation point that the RTL must reproduce.
Inputs, affine weights, and affine biases are signed Q12.  Variance therefore
uses Q24, while inverse standard deviation and output-scale reciprocals use
Q20.  Division is round-to-nearest, ties-to-even throughout.
"""

from __future__ import annotations

from dataclasses import dataclass
import math

import numpy as np


@dataclass(frozen=True)
class FixedLayerNormFormat:
    value_fraction_bits: int = 12
    reciprocal_fraction_bits: int = 20
    epsilon: float = 1e-5

    @property
    def value_scale(self) -> int:
        return 1 << self.value_fraction_bits

    @property
    def reciprocal_scale(self) -> int:
        return 1 << self.reciprocal_fraction_bits

    @property
    def epsilon_q(self) -> int:
        return round(self.epsilon * (1 << (2 * self.value_fraction_bits)))


DEFAULT_FORMAT = FixedLayerNormFormat()


def round_divide_ties_to_even(numerator: int, denominator: int) -> int:
    """Return numerator / denominator rounded to nearest, ties to even."""

    if denominator <= 0:
        raise ValueError("denominator must be positive")
    negative = numerator < 0
    quotient, remainder = divmod(abs(int(numerator)), int(denominator))
    twice_remainder = remainder * 2
    if twice_remainder > denominator or (
        twice_remainder == denominator and (quotient & 1)
    ):
        quotient += 1
    return -quotient if negative else quotient


def integer_sqrt_nearest(value: int) -> int:
    """Return sqrt(value) rounded to the nearest non-negative integer."""

    if value < 0:
        raise ValueError("square-root input must be non-negative")
    lower = math.isqrt(value)
    distance_lower = value - lower * lower
    distance_upper = (lower + 1) * (lower + 1) - value
    return lower + 1 if distance_upper < distance_lower else lower


def quantize_q12(values: np.ndarray) -> np.ndarray:
    """Quantize finite real values to the signed Q12 ingress/parameter ABI."""

    values64 = np.asarray(values, dtype=np.float64)
    if not np.all(np.isfinite(values64)):
        raise ValueError("fixed LayerNorm values must be finite")
    scaled = np.rint(values64 * DEFAULT_FORMAT.value_scale)
    if np.any(scaled < -32768) or np.any(scaled > 32767):
        raise OverflowError("value is outside the signed Q12 range")
    return scaled.astype(np.int16)


def reciprocal_scale_q20(output_scale: float) -> int:
    """Encode 1/output_scale as an unsigned Q20 configuration word."""

    if not math.isfinite(output_scale) or output_scale <= 0:
        raise ValueError("output scale must be finite and positive")
    encoded = round((1.0 / output_scale) * DEFAULT_FORMAT.reciprocal_scale)
    if encoded < 0 or encoded > 0xFFFFFFFF:
        raise OverflowError("output reciprocal does not fit uint32 Q20")
    return encoded


def fixed_layer_norm_q12(
    values_q12: np.ndarray,
    weights_q12: np.ndarray,
    biases_q12: np.ndarray,
    output_reciprocal_q20: int,
    *,
    epsilon_q24: int = DEFAULT_FORMAT.epsilon_q,
) -> np.ndarray:
    """Evaluate the integer LayerNorm contract and return saturated INT8."""

    values = np.asarray(values_q12, dtype=np.int16)
    weights = np.asarray(weights_q12, dtype=np.int16)
    biases = np.asarray(biases_q12, dtype=np.int16)
    if values.ndim != 1 or values.size == 0 or values.size > 158:
        raise ValueError("LayerNorm vector length must be between 1 and 158")
    if weights.shape != values.shape or biases.shape != values.shape:
        raise ValueError("value, weight, and bias vectors must have equal shape")
    if not 0 <= int(output_reciprocal_q20) <= 0xFFFFFFFF:
        raise ValueError("output reciprocal must fit uint32")
    if epsilon_q24 < 0:
        raise ValueError("epsilon_q24 must be non-negative")

    length = int(values.size)
    integer_values = [int(value) for value in values]
    mean_q12 = round_divide_ties_to_even(sum(integer_values), length)
    square_sum_q24 = sum((value - mean_q12) ** 2 for value in integer_values)
    variance_q24 = round_divide_ties_to_even(square_sum_q24, length)
    std_q12 = integer_sqrt_nearest(variance_q24 + int(epsilon_q24))
    if std_q12 == 0:
        raise ZeroDivisionError("epsilon and variance produced a zero standard deviation")
    inverse_std_q20 = round_divide_ties_to_even(
        1 << (DEFAULT_FORMAT.value_fraction_bits +
              DEFAULT_FORMAT.reciprocal_fraction_bits),
        std_q12,
    )

    result = np.empty(length, dtype=np.int8)
    for index, (value, weight, bias) in enumerate(
        zip(integer_values, weights, biases)
    ):
        normalized_q12 = round_divide_ties_to_even(
            (value - mean_q12) * inverse_std_q20,
            DEFAULT_FORMAT.reciprocal_scale,
        )
        affine_q12 = round_divide_ties_to_even(
            normalized_q12 * int(weight), DEFAULT_FORMAT.value_scale
        ) + int(bias)
        output = round_divide_ties_to_even(
            affine_q12 * int(output_reciprocal_q20),
            1 << (DEFAULT_FORMAT.value_fraction_bits +
                  DEFAULT_FORMAT.reciprocal_fraction_bits),
        )
        result[index] = max(-127, min(127, output))
    return result


def fixed_layer_norm_from_float(
    values: np.ndarray,
    weights: np.ndarray,
    biases: np.ndarray,
    output_scale: float,
) -> np.ndarray:
    """Convenience wrapper used by host qualification and vector generation."""

    return fixed_layer_norm_q12(
        quantize_q12(values),
        quantize_q12(weights),
        quantize_q12(biases),
        reciprocal_scale_q20(output_scale),
    )
