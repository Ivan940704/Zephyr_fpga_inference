"""CP5 isolated-subsystem reference and structural regression.

The executable model checks the controller-visible memory responses for every
job in two complete frames.  The companion SystemVerilog testbench performs
the connected frozen-PE differential; structural checks below make that A/B
intent and the isolated component wiring reviewable even on hosts without an
HDL simulator.
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl" / "sequential_v4_sparse_memory_subsystem.sv"
TB = ROOT / "tb" / "tb_sequential_v4_sparse_memory_subsystem.sv"
IMAGE_PATH = ROOT / "imports" / "fixtures" / "v4" / "parameters_v4.bin"

sys.path.insert(0, str(ROOT / "tests"))

from scatter_service_model import ScatterServiceModel  # noqa: E402
from traffic_oracle import (  # noqa: E402
    ActiveListTrace,
    DENSE_BYTES_PER_FRAME,
    FRAME_STAGE_ORDER,
    LOGICAL_SOURCE_CAPACITY,
    LUT_BYTES_PER_RESET,
    STAGE_RULES,
    accepted_r_bytes,
    load_v4_layout,
    plan_lut_transfer,
    plan_stage,
)


COMPONENT_SOURCES = {
    "sparse_union_planner_v1": ROOT / "rtl" / "sparse_union_planner_v1.sv",
    "sparse_memory_service_v1": ROOT / "rtl" / "sparse_memory_service_v1.sv",
    "sparse_recurrent_context_store_v1": (
        ROOT / "rtl" / "sparse_recurrent_context_store_v1.sv"
    ),
    "sequential_pe_job_controller": (
        ROOT
        / "imports"
        / "memory_v4"
        / "memory"
        / "sequential_pe_job_controller.v"
    ),
    "pe_array_datapath": (
        ROOT / "imports" / "pe_v1" / "rtl" / "top" / "pe_array_datapath.v"
    ),
}

INSTANCE_NAMES = {
    "sparse_union_planner_v1": "u_sparse_union_planner",
    "sparse_memory_service_v1": "u_sparse_memory_service",
    "sparse_recurrent_context_store_v1": "u_sparse_context_store",
    "sequential_pe_job_controller": "u_job_controller",
    "pe_array_datapath": "u_pe_array_datapath",
}

NEW_ABI_PORTS = {
    "sparse_load_enable",
    "context_port_owner",
    "planner_error_valid",
    "planner_error_code",
    "planner_error_detail",
    "stage_diag_valid",
    "stage_diag_success",
    "stage_diag_stage_id",
    "stage_diag_sparse_enable",
    "stage_diag_fallback_full",
    "stage_dense_reference_bytes",
    "stage_planned_bytes",
    "stage_actual_bytes",
    "stage_saved_bytes",
    "stage_union_count0",
    "stage_union_count1",
    "stage_copy_command_count",
    "stage_ar_burst_count",
    "stage_load_cycles",
    "epoch_lut_actual_bytes",
}


def _strip_comments_and_strings(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.DOTALL)
    source = re.sub(r"//[^\n]*", " ", source)
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', source)


def _balanced_region(source: str, opening: int) -> tuple[str, int]:
    """Return text inside the parenthesis at *opening* and its closing index."""

    assert source[opening] == "("
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "(":
            depth += 1
        elif source[index] == ")":
            depth -= 1
            if depth == 0:
                return source[opening + 1 : index], index
    raise AssertionError("unterminated parenthesized region")


def _module_ports(source: str, module: str) -> set[str]:
    clean = _strip_comments_and_strings(source)
    match = re.search(rf"\bmodule\s+{re.escape(module)}\b", clean)
    assert match, f"missing module {module}"
    cursor = match.end()
    parameter = re.match(r"\s*#\s*\(", clean[cursor:])
    if parameter:
        parameter_open = cursor + parameter.end() - 1
        _, cursor = _balanced_region(clean, parameter_open)
        cursor += 1
    port_open = clean.find("(", cursor)
    assert port_open >= 0, f"missing port list for {module}"
    header, _ = _balanced_region(clean, port_open)
    ports: set[str] = set()
    for declaration in header.split(","):
        declaration = declaration.strip()
        if not re.match(r"^(input|output|inout)\b", declaration):
            continue
        identifiers = re.findall(r"[A-Za-z_]\w*", declaration)
        assert identifiers, f"cannot parse {module} port declaration"
        ports.add(identifiers[-1])
    return ports


def _instance_connections(source: str, module: str, instance: str) -> set[str]:
    clean = _strip_comments_and_strings(source)
    match = re.search(
        rf"\b{re.escape(module)}\b(?:\s*#\s*\(.*?\))?\s+"
        rf"{re.escape(instance)}\s*\(",
        clean,
        flags=re.DOTALL,
    )
    assert match, f"missing instance {instance} of {module}"
    opening = match.end() - 1
    body, _ = _balanced_region(clean, opening)
    return set(re.findall(r"\.([A-Za-z_]\w*)\s*\(", body))


def _assert_balanced_hdl(source: str) -> None:
    clean = _strip_comments_and_strings(source)
    pairs = {"(": ")", "[": "]", "{": "}"}
    closing = {value: key for key, value in pairs.items()}
    stack: list[str] = []
    for character in clean:
        if character in pairs:
            stack.append(character)
        elif character in closing:
            assert stack and stack[-1] == closing[character]
            stack.pop()
    assert not stack

    for begin_token, end_token in (
        ("module", "endmodule"),
        ("begin", "end"),
        ("case", "endcase"),
        ("task", "endtask"),
        ("function", "endfunction"),
    ):
        assert len(re.findall(rf"\b{begin_token}\b", clean)) == len(
            re.findall(rf"\b{end_token}\b", clean)
        ), f"unbalanced {begin_token}/{end_token}"


def _two_frame_trace() -> ActiveListTrace:
    records = []
    for frame_id in range(2):
        for logical_id, capacity in LOGICAL_SOURCE_CAPACITY.items():
            # Deterministic, scattered, non-dense lists.  Every logical list is
            # present, including empty-capable recurrent history at frame zero.
            indices = [
                source
                for source in range(capacity)
                if (source * 17 + logical_id * 13 + frame_id * 7) % 11 in (0, 1)
            ]
            records.append(
                {
                    "frame_id": frame_id,
                    "logical_id": logical_id,
                    "ordered_active_indices": indices,
                }
            )
    return ActiveListTrace.from_records(records, name="cp5-two-frame-scattered")


def _selection_sources(trace, frame_id, matrix_rule, context):
    if matrix_rule.dense:
        return None
    requirement = matrix_rule.requirement
    assert requirement is not None
    logical_id = requirement.logical_ids[context]
    source_frame = frame_id + requirement.frame_delta
    indices = None if source_frame < 0 else trace.get(source_frame, logical_id)
    if indices is None:
        assert requirement.missing_is_empty
        return ()
    return indices


def test_wrapper_abi_and_component_connections_are_closed_and_isolated():
    source = RTL.read_text(encoding="utf-8")
    assert "module sequential_v4_sparse_memory_subsystem" in source
    assert NEW_ABI_PORTS <= _module_ports(
        source, "sequential_v4_sparse_memory_subsystem"
    )
    assert '`include "sparse_memory_v4_map_v1.vh"' in source
    assert "../" not in source
    assert "rtl/memory/" not in source
    assert "sequential_v4_pe_memory_subsystem" not in source
    assert "!context_producer_open_valid" in source
    assert ".parameter_base_addr(sampled_parameter_base_q)" in source
    assert "sampled_parameter_base_q <= parameter_base_addr" in source
    for gated_store_signal in (
        "store_producer_open_valid",
        "store_state_write_valid",
        "store_active_cmd_valid",
        "store_commit_valid",
    ):
        assert gated_store_signal in source
    assert "context_owner_q == CTX_CONTROLLER" in source
    assert "service_plan_accepted_q" in source
    assert "unqualified_service_done" in source

    for module, path in COMPONENT_SOURCES.items():
        assert path.is_file()
        assert path.resolve().is_relative_to(ROOT.resolve())
        declared = _module_ports(path.read_text(encoding="utf-8"), module)
        connected = _instance_connections(source, module, INSTANCE_NAMES[module])
        assert connected == declared, (
            module,
            sorted(declared - connected),
            sorted(connected - declared),
        )


def test_hdl_sources_pass_structural_syntax_smoke():
    _assert_balanced_hdl(RTL.read_text(encoding="utf-8"))
    _assert_balanced_hdl(TB.read_text(encoding="utf-8"))


def test_connected_tb_freezes_two_frame_dense_sparse_observables():
    source = TB.read_text(encoding="utf-8")
    assert "module tb_sequential_v4_sparse_memory_subsystem" in source
    assert source.count("run_frame(0);") == 2
    assert source.count("run_frame(1);") == 2
    assert "selected_sparse_mode = 1'b0" in source
    assert "selected_sparse_mode = 1'b1" in source
    assert "compare_against_dense = 1'b1" in source
    for observable in (
        "dense_feature_stream",
        "dense_coefficient_stream",
        "dense_state_stream",
        "dense_active_stream",
        "dense_weight_rsp_stream",
        "dense_param_rsp_stream",
    ):
        assert observable in source
    assert "completed_stage_loads == 24" in source
    assert "completed_jobs == 60" in source
    assert "sparse_two_frame_stage_bytes < dense_two_frame_stage_bytes" in source
    assert "connected_oracle_bytes" in source
    assert "axi_accepted_r_bytes" in source
    assert "planner and context producer handshook in one cycle" in source
    assert "post-commit descriptor changed under backpressure" in source
    assert "../" not in source
    assert "rtl/memory/" not in source


def test_two_frame_dense_sparse_controller_memory_responses_are_bit_exact():
    layout = load_v4_layout()
    image = IMAGE_PATH.read_bytes()
    trace = _two_frame_trace()
    dense = ScatterServiceModel(image, image_base=0x1000_0000)
    sparse = ScatterServiceModel(image, image_base=0x1000_0000)
    dense_bytes = 0
    sparse_bytes = 0
    job_count = 0
    response_count = 0
    dense_digest = hashlib.sha256()
    sparse_digest = hashlib.sha256()

    for frame_id in range(2):
        # The shared connected wrapper permits numeric order; all predecessor
        # lists for a stage have been committed earlier in this order.
        for stage_id in range(12):
            stage = layout.stage(stage_id)
            stage_rule = STAGE_RULES[stage_id]
            traffic = plan_stage(
                layout,
                trace,
                frame_id=frame_id,
                stage_id=stage_id,
                parameter_base_addr=0x1000_0000,
            )
            bitmaps = [0, 0]
            for selection in traffic.matrix_selections:
                if not selection.dense:
                    bitmaps[selection.matrix_id] = sum(
                        1 << source for source in selection.active_sources
                    )

            dense.load(stage_id, tuple(bitmaps), sparse_enable=False)
            sparse.load(stage_id, tuple(bitmaps), sparse_enable=True)
            dense_bytes += dense.actual_bytes
            sparse_bytes += sparse.actual_bytes
            assert dense.actual_bytes == stage.transfer_bytes
            assert sparse.actual_bytes == traffic.planned_bytes
            assert sparse.actual_bytes == accepted_r_bytes(
                traffic.accepted_r_beats
            )

            for context in range(stage_rule.context_count):
                job_count += 1
                for matrix, matrix_rule in zip(
                    stage.matrices, stage_rule.matrices, strict=True
                ):
                    selected = _selection_sources(
                        trace, frame_id, matrix_rule, context
                    )
                    sources = (
                        range(matrix.source_count) if selected is None else selected
                    )
                    for source_index in sources:
                        for row_tile in range(matrix.row_tiles):
                            dense_word = dense.read_weight(
                                matrix.matrix_id, source_index, row_tile
                            )
                            sparse_word = sparse.read_weight(
                                matrix.matrix_id, source_index, row_tile
                            )
                            assert sparse_word == dense_word
                            identity = bytes(
                                (
                                    frame_id,
                                    stage_id,
                                    context,
                                    matrix.matrix_id,
                                    source_index & 0xFF,
                                    source_index >> 8,
                                    row_tile,
                                )
                            )
                            dense_digest.update(identity + dense_word)
                            sparse_digest.update(identity + sparse_word)
                            response_count += 1

                for row_tile in range(stage.parameters.row_tiles):
                    dense_record = dense.read_parameter(row_tile)
                    sparse_record = sparse.read_parameter(row_tile)
                    assert sparse_record == dense_record
                    identity = bytes((frame_id, stage_id, context, row_tile))
                    dense_digest.update(identity + dense_record)
                    sparse_digest.update(identity + sparse_record)
                    response_count += 1

            dense.release(stage_id)
            sparse.release(stage_id)

    assert FRAME_STAGE_ORDER == (0, 1, 2, 3, 6, 9, 4, 7, 10, 5, 8, 11)
    assert job_count == 60
    assert response_count > 0
    assert dense_digest.digest() == sparse_digest.digest()
    assert dense_bytes == 2 * DENSE_BYTES_PER_FRAME
    assert sparse_bytes < dense_bytes
    assert plan_lut_transfer(
        layout, parameter_base_addr=0x1000_0000
    ).planned_bytes == LUT_BYTES_PER_RESET
