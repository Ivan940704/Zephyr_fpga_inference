from pathlib import Path

import numpy as np
import pytest

from software.fixed_layernorm import (
    DEFAULT_FORMAT,
    fixed_layer_norm_from_float,
    fixed_layer_norm_q12,
    integer_sqrt_nearest,
    quantize_q12,
    reciprocal_scale_q20,
    round_divide_ties_to_even,
)
from software.pynq.accelerator_inference import (
    CENTER_SIZES,
    CONTEXT_COUNTS,
    FREQ_CUTOFFS,
    NEIGHBOR_SIZES,
    RuntimeParameters,
    _reflect_window_source,
    build_subband_payload,
    prepare_fullband_input,
)
from software.pynq.build_inference_bundle import build


ROOT = Path(__file__).resolve().parents[2]


@pytest.mark.parametrize(
    ("numerator", "denominator", "expected"),
    [
        (1, 2, 0),
        (3, 2, 2),
        (5, 2, 2),
        (7, 2, 4),
        (-1, 2, 0),
        (-3, 2, -2),
        (8, 3, 3),
        (-8, 3, -3),
    ],
)
def test_round_divide_uses_symmetric_ties_to_even(numerator, denominator, expected):
    assert round_divide_ties_to_even(numerator, denominator) == expected


def test_integer_sqrt_selects_nearest_root():
    assert [integer_sqrt_nearest(value) for value in (0, 1, 2, 3, 4, 6, 7, 8, 9)] == [
        0, 1, 1, 2, 2, 2, 3, 3, 3
    ]


def test_q12_range_and_zero_variance_epsilon_contract():
    assert quantize_q12(np.asarray([-8.0, 7.99975])).tolist() == [-32768, 32767]
    with pytest.raises(OverflowError):
        quantize_q12(np.asarray([8.0]))
    values = quantize_q12(np.full(8, 0.25))
    weights = quantize_q12(np.ones(8))
    biases = quantize_q12(np.linspace(-0.5, 0.5, 8))
    actual = fixed_layer_norm_q12(
        values, weights, biases, reciprocal_scale_q20(0.125)
    )
    expected = np.clip(np.rint(np.linspace(-0.5, 0.5, 8) / 0.125), -127, 127)
    assert np.array_equal(actual, expected.astype(np.int8))
    assert DEFAULT_FORMAT.epsilon_q == 168


def _fixed_subband_payload(magnitude, projection, parameters):
    fullband_feature = np.tile(
        projection.astype(np.float32) * np.float32(parameters.fb_projection_scale), 4
    )
    vectors = []
    for band, (lower, upper, center, neighbor, contexts) in enumerate(
        zip(
            FREQ_CUTOFFS[:-1],
            FREQ_CUTOFFS[1:],
            CENTER_SIZES,
            NEIGHBOR_SIZES,
            CONTEXT_COUNTS,
        )
    ):
        source = _reflect_window_source(magnitude, lower, upper, neighbor)
        noisy_width = center + 2 * neighbor
        for context in range(contexts):
            noisy = source[context * center : context * center + noisy_width]
            fullband = fullband_feature[
                lower + context * center : lower + (context + 1) * center
            ]
            vectors.append(
                fixed_layer_norm_from_float(
                    np.concatenate((noisy, fullband)),
                    parameters.sb_weights[band],
                    parameters.sb_biases[band],
                    parameters.sb_input_scales[band],
                )
            )
    return np.concatenate(vectors)


def test_q12_contract_is_within_one_lsb_on_saved_real_frames(tmp_path):
    runtime_path = tmp_path / "runtime_parameters.npz"
    build(ROOT / "upstream/parameters/manifest.json", runtime_path)
    parameters = RuntimeParameters.load(runtime_path)
    with np.load(
        ROOT / "rtl/reports/accelerator_full_board/inference_result.npz",
        allow_pickle=False,
    ) as result:
        magnitudes = np.sqrt(np.abs(result["noisy_stft"][:256])).T.astype(np.float32)
        projections = np.asarray(result["fb_projections"], dtype=np.int8)
        saved_subbands = np.asarray(result["sb_payloads"], dtype=np.int8)

    fullband_differences = []
    subband_differences = []
    for magnitude, projection, saved_subband in zip(
        magnitudes, projections, saved_subbands
    ):
        float_fullband = prepare_fullband_input(magnitude, parameters)
        fixed_fullband = fixed_layer_norm_from_float(
            magnitude[:64],
            parameters.fb_weight,
            parameters.fb_bias,
            parameters.fb_input_scale,
        )
        assert np.array_equal(
            build_subband_payload(magnitude, projection, parameters), saved_subband
        )
        fixed_subband = _fixed_subband_payload(magnitude, projection, parameters)
        fullband_differences.extend(
            fixed_fullband.astype(np.int16) - float_fullband.astype(np.int16)
        )
        subband_differences.extend(
            fixed_subband.astype(np.int16) - saved_subband.astype(np.int16)
        )

    fullband_differences = np.asarray(fullband_differences)
    subband_differences = np.asarray(subband_differences)
    assert np.max(np.abs(fullband_differences)) <= 1
    assert np.max(np.abs(subband_differences)) <= 1
    assert np.mean(fullband_differences == 0) >= 0.997
    assert np.mean(subband_differences == 0) >= 0.993
