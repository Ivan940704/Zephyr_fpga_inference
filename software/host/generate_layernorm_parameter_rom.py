#!/usr/bin/env python3
"""Generate checked Q12 LayerNorm ROM data from the frozen model archive."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
from pathlib import Path


PROFILE_SPECS = (
    (
        "fullband",
        "fb_model.pre_layer_norm.weight",
        "fb_model.pre_layer_norm.bias",
        "fb_model.sequence_model.layers.0.cell",
        64,
    ),
    (
        "subband_0",
        "sb_model.sb_models.0.pre_layer_norm.weight",
        "sb_model.sb_models.0.pre_layer_norm.bias",
        "sb_model.sb_models.0.sequence_model.layers.0.cell",
        46,
    ),
    (
        "subband_1",
        "sb_model.sb_models.1.pre_layer_norm.weight",
        "sb_model.sb_models.1.pre_layer_norm.bias",
        "sb_model.sb_models.1.sequence_model.layers.0.cell",
        94,
    ),
    (
        "subband_2",
        "sb_model.sb_models.2.pre_layer_norm.weight",
        "sb_model.sb_models.2.pre_layer_norm.bias",
        "sb_model.sb_models.2.sequence_model.layers.0.cell",
        158,
    ),
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_tensor(blob: bytes, metadata: dict) -> list[float]:
    start = int(metadata["offset"])
    end = start + int(metadata["nbytes"])
    raw = blob[start:end]
    if sha256(raw) != metadata["sha256"]:
        raise ValueError(f"tensor checksum mismatch at offset {start}")
    dtype = metadata["dtype"]
    code = {"float32": "f", "float64": "d"}.get(dtype)
    if code is None:
        raise ValueError(f"unsupported tensor dtype: {dtype}")
    item_bytes = struct.calcsize(code)
    return list(struct.unpack(f"<{len(raw) // item_bytes}{code}", raw))


def quantize_q12(value: float) -> int:
    if not math.isfinite(value):
        raise ValueError("LayerNorm parameter must be finite")
    encoded = round(value * 4096.0)
    if encoded < -32768 or encoded > 32767:
        raise OverflowError(f"LayerNorm parameter {value} is outside signed Q12")
    return encoded


def reciprocal_q20(scale: float) -> int:
    if not math.isfinite(scale) or scale <= 0.0:
        raise ValueError(f"invalid output scale: {scale}")
    encoded = round((1.0 / scale) * (1 << 20))
    if encoded < 0 or encoded > 0xFFFFFFFF:
        raise OverflowError("output reciprocal does not fit uint32 Q20")
    return encoded


def float32(value: float) -> float:
    return struct.unpack("<f", struct.pack("<f", value))[0]


def reflect_source(lower: int, upper: int, neighbor: int) -> list[int]:
    if lower == 0:
        body = list(range(0, upper + neighbor))
        return list(range(neighbor, 0, -1)) + body
    if upper == 256:
        body = list(range(lower - neighbor, 256))
        return body + list(range(254, 254 - neighbor, -1))
    return list(range(lower - neighbor, upper + neighbor))


def build_source_indices() -> list[int]:
    indices: list[int] = []
    for lower, upper, center, neighbor, contexts in zip(
        (0, 32, 128), (32, 128, 256), (8, 32, 64),
        (15, 15, 15), (4, 3, 2)
    ):
        source = reflect_source(lower, upper, neighbor)
        noisy_width = center + 2 * neighbor
        for context in range(contexts):
            start = context * center
            indices.extend(source[start:start + noisy_width])
            indices.extend(
                256 + (index % 64)
                for index in range(
                    lower + context * center,
                    lower + (context + 1) * center,
                )
            )
    if len(indices) != 782 or any(index < 0 or index >= 320 for index in indices):
        raise AssertionError("subband source map is not the expected 782x9-bit layout")
    return indices


def write_lines(path: Path, lines: list[str]) -> str:
    data = ("\n".join(lines) + "\n").encode("ascii")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return sha256(data)


def generate(manifest_path: Path, output_dir: Path) -> None:
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    blob_path = manifest_path.parent / manifest["storage"]["file"]
    blob = blob_path.read_bytes()
    if sha256(blob) != manifest["storage"]["sha256"]:
        raise ValueError("source parameter archive checksum mismatch")

    initialization = []
    vectors = []
    profiles = []
    offset = 0
    unlowered = manifest["unlowered_parameters"]
    for profile_id, (name, weight_key, bias_key, operator_key, length) in enumerate(
        PROFILE_SPECS
    ):
        weights = read_tensor(blob, unlowered[weight_key])
        biases = read_tensor(blob, unlowered[bias_key])
        scale_metadata = manifest["operators"][operator_key]["tensors"]["input_scale"]
        scales = read_tensor(blob, scale_metadata)
        if len(weights) != length or len(biases) != length or len(scales) != 1:
            raise ValueError(f"unexpected {name} parameter shape")
        reciprocal = reciprocal_q20(scales[0])
        quantized_weights = [quantize_q12(value) for value in weights]
        quantized_biases = [quantize_q12(value) for value in biases]
        for index, (weight, bias) in enumerate(zip(quantized_weights, quantized_biases)):
            packed = ((bias & 0xFFFF) << 16) | (weight & 0xFFFF)
            initialization.append(
                f"parameter_memory[{offset + index}] = 32'h{packed:08x};"
            )
            vectors.append(f"D {profile_id} {index} {weight} {bias}")
        profiles.append(
            {
                "profile_id": profile_id,
                "name": name,
                "offset": offset,
                "length": length,
                "output_scale": scales[0],
                "output_reciprocal_q20": reciprocal,
                "weight_q12_min": min(quantized_weights),
                "weight_q12_max": max(quantized_weights),
                "bias_q12_min": min(quantized_biases),
                "bias_q12_max": max(quantized_biases),
            }
        )
        offset += length

    init_path = output_dir / "layernorm_parameter_rom_q12_init.vh"
    vector_path = output_dir / "layernorm_parameter_rom_vectors.txt"
    init_sha = write_lines(init_path, initialization)
    vector_sha = write_lines(vector_path, [str(len(vectors)), *vectors])

    projection_scale_metadata = manifest["operators"]["fb_model.proj"]["tensors"]
    projection_scale_metadata = projection_scale_metadata["output_scale"]
    projection_scale = read_tensor(blob, projection_scale_metadata)[0]
    projection_scale_f32 = float32(projection_scale)
    projection_q12 = [
        quantize_q12(float32(float32(value) * projection_scale_f32))
        for value in range(-127, 128)
    ]
    projection_init = [
        f"projection_dequant_memory[{index}] = 16'h{value & 0xFFFF:04x};"
        for index, value in enumerate(projection_q12)
    ]
    projection_path = output_dir / "projection_dequant_q12_init.vh"
    projection_sha = write_lines(projection_path, projection_init)

    source_indices = build_source_indices()
    source_init = [
        f"source_index_memory[{index}] = 9'h{value:03x};"
        for index, value in enumerate(source_indices)
    ]
    source_path = output_dir / "subband_source_index_init.vh"
    source_sha = write_lines(source_path, source_init)

    metadata = {
        "schema": "zephyr.layernorm-parameter-rom-q12.v1",
        "source_manifest": "upstream/parameters/manifest.json",
        "source_manifest_sha256": sha256(manifest_bytes),
        "source_parameter_blob": "upstream/parameters/parameters.bin",
        "source_parameter_blob_sha256": sha256(blob),
        "numeric_contract": "signed_Q12_affine_and_values_reciprocal_Q20",
        "parameter_entries": offset,
        "profiles": profiles,
        "parameter_init_sha256": init_sha,
        "parameter_vector_sha256": vector_sha,
        "projection_scale_float64": projection_scale,
        "projection_scale_float32": projection_scale_f32,
        "projection_dequant_entries": len(projection_q12),
        "projection_dequant_init_sha256": projection_sha,
        "subband_source_entries": len(source_indices),
        "subband_source_init_sha256": source_sha,
    }
    metadata_path = output_dir / "layernorm_parameter_rom_metadata.json"
    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(
        "LAYERNORM_PARAMETER_ROM_GENERATED "
        f"entries={offset} source_entries={len(source_indices)} "
        f"metadata={metadata_path}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    generate(args.manifest, args.output_dir)


if __name__ == "__main__":
    main()
