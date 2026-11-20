#!/usr/bin/env python3
"""Generate real-frame vectors for the PL LayerNorm feature coordinator."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np


SCRIPT_REPO_ROOT = Path(__file__).resolve().parents[2]
WORKING_REPO_ROOT = Path.cwd().resolve()
REPO_ROOT = (
    WORKING_REPO_ROOT
    if (WORKING_REPO_ROOT / "software" / "fixed_layernorm.py").is_file()
    else SCRIPT_REPO_ROOT
)
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from software.fixed_layernorm import fixed_layer_norm_from_float, quantize_q12  # noqa: E402
from software.pynq.accelerator_inference import (  # noqa: E402
    CENTER_SIZES,
    CONTEXT_COUNTS,
    FREQ_CUTOFFS,
    NEIGHBOR_SIZES,
    RuntimeParameters,
    _reflect_window_source,
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fixed_subband_payload(
    magnitude: np.ndarray,
    projection: np.ndarray,
    parameters: RuntimeParameters,
) -> np.ndarray:
    projection_feature = np.tile(
        projection.astype(np.float32) * np.float32(parameters.fb_projection_scale), 4
    )
    vectors = []
    for band, (lower, upper, center, neighbor, contexts) in enumerate(
        zip(
            FREQ_CUTOFFS[:-1], FREQ_CUTOFFS[1:], CENTER_SIZES,
            NEIGHBOR_SIZES, CONTEXT_COUNTS,
        )
    ):
        source = _reflect_window_source(magnitude, lower, upper, neighbor)
        noisy_width = center + 2 * neighbor
        for context in range(contexts):
            noisy = source[context * center:context * center + noisy_width]
            fullband = projection_feature[
                lower + context * center:lower + (context + 1) * center
            ]
            vector = np.concatenate((noisy, fullband))
            vectors.append(
                fixed_layer_norm_from_float(
                    vector,
                    parameters.sb_weights[band],
                    parameters.sb_biases[band],
                    parameters.sb_input_scales[band],
                )
            )
    payload = np.concatenate(vectors).astype(np.int8, copy=False)
    if payload.shape != (782,):
        raise AssertionError(f"unexpected fixed subband payload shape {payload.shape}")
    return payload


def write_integer_block(handle, values: np.ndarray, width: int = 16) -> None:
    flat = np.asarray(values).reshape(-1)
    for start in range(0, flat.size, width):
        handle.write(" ".join(str(int(value)) for value in flat[start:start + width]))
        handle.write("\n")


def generate(
    result_path: Path,
    runtime_parameter_path: Path,
    output_path: Path,
    metadata_path: Path,
    frame_indices: list[int],
    rescale_magnitude_max: float | None,
) -> None:
    parameters = RuntimeParameters.load(runtime_parameter_path)
    parameters.validate()

    with np.load(result_path, allow_pickle=False) as archive:
        hardware_bins = np.asarray(archive["hardware_bins"], dtype=np.complex64)
        projections = np.asarray(archive["fb_projections"], dtype=np.int8)
    if hardware_bins.shape[0] != 256 or projections.shape[1] != 64:
        raise ValueError("saved board result has incompatible feature shapes")
    if any(index < 0 or index >= hardware_bins.shape[1] for index in frame_indices):
        raise IndexError("requested frame index is outside the saved board result")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    records = []
    with output_path.open("w", encoding="ascii", newline="\n") as handle:
        handle.write(f"{len(frame_indices)}\n")
        for frame_index in frame_indices:
            magnitude = np.abs(hardware_bins[:, frame_index]).astype(np.float32)
            original_magnitude_max = float(magnitude.max())
            magnitude_scale = 1.0
            if rescale_magnitude_max is not None and (
                original_magnitude_max > rescale_magnitude_max
            ):
                magnitude_scale = rescale_magnitude_max / original_magnitude_max
                magnitude = (magnitude * np.float32(magnitude_scale)).astype(np.float32)
            magnitude_q12 = quantize_q12(magnitude)
            fullband = fixed_layer_norm_from_float(
                magnitude[:64], parameters.fb_weight, parameters.fb_bias,
                parameters.fb_input_scale,
            )
            projection = projections[frame_index]
            subbands = fixed_subband_payload(magnitude, projection, parameters)
            handle.write(f"{frame_index}\n")
            write_integer_block(handle, magnitude_q12)
            write_integer_block(handle, fullband)
            write_integer_block(handle, projection)
            write_integer_block(handle, subbands)
            records.append(
                {
                    "saved_frame_index": frame_index,
                    "original_magnitude_max": original_magnitude_max,
                    "fixture_magnitude_scale": magnitude_scale,
                    "magnitude_q12_min": int(magnitude_q12.min()),
                    "magnitude_q12_max": int(magnitude_q12.max()),
                    "fullband_int8_sha256": hashlib.sha256(fullband.tobytes()).hexdigest(),
                    "projection_int8_sha256": hashlib.sha256(projection.tobytes()).hexdigest(),
                    "subband_int8_sha256": hashlib.sha256(subbands.tobytes()).hexdigest(),
                }
            )
    metadata = {
        "schema": "zephyr.realtime-feature-coordinator-vectors.v1",
        "source_result": "rtl/reports/accelerator_full_board/inference_result.npz",
        "source_result_sha256": sha256_file(result_path),
        "runtime_parameters": "runtime_parameters.npz generated from frozen manifest",
        "runtime_parameters_sha256": sha256_file(runtime_parameter_path),
        "frame_count": len(frame_indices),
        "fixture_rescale_magnitude_max": rescale_magnitude_max,
        "fixture_note": (
            "Saved projection is injected independently; when rescaling is enabled, "
            "this is a connected arithmetic fixture, not an end-to-end model frame."
        ),
        "records": records,
        "vector_file_sha256": sha256_file(output_path),
    }
    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(
        f"REALTIME_FEATURE_COORDINATOR_VECTORS frames={len(frame_indices)} "
        f"path={output_path} sha256={metadata['vector_file_sha256']}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--saved-result", type=Path, required=True)
    parser.add_argument("--runtime-parameters", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--frame-index", type=int, action="append", required=True)
    parser.add_argument("--rescale-magnitude-max", type=float)
    args = parser.parse_args()
    generate(
        args.saved_result, args.runtime_parameters, args.output, args.metadata,
        args.frame_index, args.rescale_magnitude_max,
    )


if __name__ == "__main__":
    main()
