#!/usr/bin/env python3
"""Repack manifest tensors into compact AXI-aligned stage images.

The original parameters.bin is deliberately target-neutral and many operator
starts are not AXI-beat aligned.  This tool creates a hardware-side image where
every stage starts on a configurable boundary and every DMA transfer is a whole
number of bus beats.  For a shared-weight GSU, the source archive repeats the
same input/recurrent weights and weight scales for both gates; the hardware
image stores one copy and marks it for reuse by both gates.  The tool also emits
JSON and Verilog metadata for the FSM/PE.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


OPERATOR_EXECUTION_ORDER = [
    "fb_model.sequence_model.layers.0.cell",
    "fb_model.sequence_model.layers.1.cell",
    "fb_model.proj",
    "sb_model.sb_models.0.sequence_model.layers.0.cell",
    "sb_model.sb_models.0.sequence_model.layers.1.cell",
    "sb_model.sb_models.0.proj",
    "sb_model.sb_models.1.sequence_model.layers.0.cell",
    "sb_model.sb_models.1.sequence_model.layers.1.cell",
    "sb_model.sb_models.1.proj",
    "sb_model.sb_models.2.sequence_model.layers.0.cell",
    "sb_model.sb_models.2.sequence_model.layers.1.cell",
    "sb_model.sb_models.2.proj",
]

SHARED_GATE_TENSORS = frozenset(
    {
        "weight_ih_q",
        "weight_hh_q",
        "weight_ih_scale",
        "weight_hh_scale",
    }
)


def align_up(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def macro_name(*parts: str) -> str:
    text = "_".join(parts).upper()
    return re.sub(r"[^A-Z0-9]+", "_", text).strip("_")


def contiguous_span(tensors: dict) -> tuple[int, int]:
    ordered = sorted(tensors.items(), key=lambda item: int(item[1]["offset"]))
    start = int(ordered[0][1]["offset"])
    cursor = start
    for name, metadata in ordered:
        offset = int(metadata["offset"])
        if offset != cursor:
            raise ValueError(f"gap before tensor {name}: expected {cursor}, got {offset}")
        cursor = offset + int(metadata["nbytes"])
    return start, cursor


def pack_stage(
    source: bytes,
    tensors: dict,
    *,
    share_gsu_gate_weights: bool,
) -> tuple[bytes, dict, int]:
    """Pack one operator and remove the duplicated half of shared GSU tensors."""

    source_start, source_end = contiguous_span(tensors)
    payload = bytearray()
    tensor_layout = {}

    ordered = sorted(tensors.items(), key=lambda item: int(item[1]["offset"]))
    for tensor_name, metadata in ordered:
        source_offset = int(metadata["offset"])
        source_nbytes = int(metadata["nbytes"])
        source_shape = list(metadata["shape"])
        tensor_bytes = source[source_offset : source_offset + source_nbytes]
        if len(tensor_bytes) != source_nbytes:
            raise ValueError(f"source tensor {tensor_name} is truncated")

        packed_shape = list(source_shape)
        gate_shared = share_gsu_gate_weights and tensor_name in SHARED_GATE_TENSORS
        if gate_shared:
            if not source_shape or source_shape[0] % 2:
                raise ValueError(
                    f"shared-gate tensor {tensor_name} must have an even first dimension"
                )
            if source_nbytes % 2:
                raise ValueError(
                    f"shared-gate tensor {tensor_name} must have an even byte count"
                )
            half = source_nbytes // 2
            if tensor_bytes[:half] != tensor_bytes[half:]:
                raise ValueError(
                    f"shared-gate tensor {tensor_name} does not contain identical halves"
                )
            tensor_bytes = tensor_bytes[:half]
            packed_shape[0] //= 2

        local_byte_offset = len(payload)
        payload.extend(tensor_bytes)
        packed = {
            "local_byte_offset": local_byte_offset,
            "nbytes": len(tensor_bytes),
            "dtype": metadata["dtype"],
            "shape": packed_shape,
            "source_offset": source_offset,
            "source_nbytes": source_nbytes,
            "source_shape": source_shape,
        }
        if gate_shared:
            packed.update(
                {
                    "gate_shared": True,
                    "gate_count": 2,
                    "packing": "store_first_gate_copy_and_reuse_for_both",
                }
            )
        tensor_layout[tensor_name] = packed

    source_payload_bytes = source_end - source_start
    if len(payload) > source_payload_bytes:
        raise ValueError("packed stage grew larger than its source span")
    return bytes(payload), tensor_layout, source_payload_bytes


def build_layout(manifest_path: Path, bus_bytes: int, stage_alignment: int):
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if bus_bytes <= 0 or bus_bytes & (bus_bytes - 1):
        raise ValueError("bus-bytes must be a positive power of two")
    if stage_alignment < bus_bytes or stage_alignment % bus_bytes:
        raise ValueError("stage-alignment must be a multiple of bus-bytes")

    storage_path = manifest_path.parent / manifest["storage"]["file"]
    source = storage_path.read_bytes()
    output = bytearray()
    stages = []

    operators = manifest["operators"]
    if set(operators) != set(OPERATOR_EXECUTION_ORDER):
        missing = set(OPERATOR_EXECUTION_ORDER) - set(operators)
        extra = set(operators) - set(OPERATOR_EXECUTION_ORDER)
        raise ValueError(f"operator set changed; missing={missing}, extra={extra}")

    shared_weights = bool(manifest.get("model", {}).get("args", {}).get("shared_weights"))
    total_payload_bytes_saved = 0

    for stage_id, operator_name in enumerate(OPERATOR_EXECUTION_ORDER):
        tensors = operators[operator_name]["tensors"]
        share_gsu_gate_weights = (
            shared_weights
            and operators[operator_name]["class"] == "IntegerGSUCellReference"
        )
        stage_payload, tensor_layout, source_payload_bytes = pack_stage(
            source,
            tensors,
            share_gsu_gate_weights=share_gsu_gate_weights,
        )
        stage_start = align_up(len(output), stage_alignment)
        output.extend(bytes(stage_start - len(output)))
        output.extend(stage_payload)

        payload_bytes = len(stage_payload)
        transfer_bytes = align_up(payload_bytes, bus_bytes)
        output.extend(bytes(stage_start + transfer_bytes - len(output)))
        packed_bytes_saved = source_payload_bytes - payload_bytes
        total_payload_bytes_saved += packed_bytes_saved

        stages.append(
            {
                "id": stage_id,
                "name": operator_name,
                "class": operators[operator_name]["class"],
                "dram_byte_offset": stage_start,
                "source_payload_bytes": source_payload_bytes,
                "payload_bytes": payload_bytes,
                "packed_bytes_saved": packed_bytes_saved,
                "transfer_bytes": transfer_bytes,
                "bram_words": transfer_bytes // bus_bytes,
                "shared_gate_weight_packing": share_gsu_gate_weights,
                "tensors": tensor_layout,
            }
        )

    layout = {
        "format_version": 2,
        "source_manifest": str(manifest_path.as_posix()),
        "bus_bytes": bus_bytes,
        "stage_alignment": stage_alignment,
        "image_bytes": len(output),
        "maximum_stage_bytes": max(stage["transfer_bytes"] for stage in stages),
        "payload_bytes_saved": total_payload_bytes_saved,
        "shared_gate_weight_packing": shared_weights,
        "shared_gate_tensor_names": sorted(SHARED_GATE_TENSORS),
        "unlowered_parameters_in_image": False,
        "stages": stages,
    }
    return bytes(output), layout


def emit_verilog(layout: dict, output_path: Path) -> None:
    lines = [
        "// Generated by rtl/tools/generate_axi_memory_image.py; do not edit.",
        "`ifndef MODEL_MEMORY_MAP_VH",
        "`define MODEL_MEMORY_MAP_VH",
        "",
        f"`define MODEL_STAGE_COUNT {len(layout['stages'])}",
        f"`define MODEL_IMAGE_BYTES 32'd{layout['image_bytes']}",
        f"`define MODEL_MAX_STAGE_BYTES 32'd{layout['maximum_stage_bytes']}",
        f"`define MODEL_PACKED_PAYLOAD_BYTES_SAVED 32'd{layout['payload_bytes_saved']}",
        f"`define MODEL_SHARED_GATE_WEIGHT_PACKING {int(layout['shared_gate_weight_packing'])}",
        "",
    ]
    for stage in layout["stages"]:
        prefix = macro_name("MODEL", stage["name"])
        lines.extend(
            [
                f"// Stage {stage['id']}: {stage['name']}",
                f"`define {prefix}_ID 8'd{stage['id']}",
                f"`define {prefix}_DRAM_OFFSET 32'd{stage['dram_byte_offset']}",
                f"`define {prefix}_SOURCE_PAYLOAD_BYTES 32'd{stage['source_payload_bytes']}",
                f"`define {prefix}_TRANSFER_BYTES 32'd{stage['transfer_bytes']}",
                f"`define {prefix}_BRAM_WORDS 32'd{stage['bram_words']}",
                f"`define {prefix}_PACKED_BYTES_SAVED 32'd{stage['packed_bytes_saved']}",
            ]
        )
        for tensor_name, tensor in stage["tensors"].items():
            tensor_prefix = macro_name(prefix, tensor_name)
            lines.append(
                f"`define {tensor_prefix}_LOCAL_BYTE_OFFSET "
                f"32'd{tensor['local_byte_offset']}"
            )
            lines.append(
                f"`define {tensor_prefix}_NBYTES 32'd{tensor['nbytes']}"
            )
            if tensor.get("gate_shared"):
                lines.append(f"`define {tensor_prefix}_GATE_SHARED 1")
                lines.append(
                    f"`define {tensor_prefix}_GATE_COUNT {tensor['gate_count']}"
                )
                lines.append(
                    f"`define {tensor_prefix}_SOURCE_NBYTES 32'd{tensor['source_nbytes']}"
                )
        lines.append("")
    lines.append("`endif")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("upstream/parameters/manifest.json"),
    )
    parser.add_argument(
        "--output-bin",
        type=Path,
        default=Path("outputs/memory/generated/parameters_axi.bin"),
    )
    parser.add_argument(
        "--output-map",
        type=Path,
        default=Path("outputs/memory/generated/memory_layout.json"),
    )
    parser.add_argument(
        "--output-vh",
        type=Path,
        default=Path("rtl/memory/model_memory_map.vh"),
    )
    parser.add_argument("--bus-bytes", type=int, default=8)
    parser.add_argument("--stage-alignment", type=int, default=64)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    image, layout = build_layout(args.manifest, args.bus_bytes, args.stage_alignment)
    args.output_bin.parent.mkdir(parents=True, exist_ok=True)
    args.output_map.parent.mkdir(parents=True, exist_ok=True)
    args.output_bin.write_bytes(image)
    args.output_map.write_text(json.dumps(layout, indent=2) + "\n", encoding="utf-8")
    emit_verilog(layout, args.output_vh)
    print(f"wrote {args.output_bin} ({len(image)} bytes)")
    print(f"wrote {args.output_map}")
    print(f"wrote {args.output_vh}")


if __name__ == "__main__":
    main()
