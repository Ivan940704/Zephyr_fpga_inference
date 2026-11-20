"""Fail-closed checks for the CP7 registered internal-fault evidence."""

from __future__ import annotations

import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports" / "cp7"
SUMMARY = REPORTS / "cp7_registered_fault_xsim_summary.txt"
INPUTS = REPORTS / "cp7_registered_fault_xsim_inputs.txt"
XSIM_LOG = REPORTS / "cp7_registered_fault_xsim.log"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _key_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if not line:
            continue
        key, separator, value = line.partition("=")
        assert separator, f"malformed evidence line: {line!r}"
        assert key not in values, f"duplicate evidence key: {key}"
        values[key] = value
    return values


def test_cp7_connected_xsim_passed_registered_fault_contract() -> None:
    values = _key_values(SUMMARY)

    assert values["checkpoint"] == "CP7"
    assert values["evidence_type"] == "Vivado_2018.3_connected_XSim"
    assert values["registered_fault_cut"] == "PASS"
    assert values["raw_fault_blocks_admission_same_cycle"] == "PASS"
    assert values["internal_abort_asserts_after_register"] == "PASS"
    assert values["checks"] == "12450566"
    assert values["dense_bytes"] == "2101088"
    assert values["sparse_bytes"] == "1052208"
    assert values["source_hash_stable"] == "1"
    assert values["runner_hash_stable"] == "1"
    assert values["status"] == "PASS"
    assert values["gate_pass"] == "1"

    log = XSIM_LOG.read_text(encoding="utf-8-sig")
    signature = (
        "PASS tb_sequential_v4_sparse_memory_subsystem "
        "checks=12450566 dense_bytes=2101088 sparse_bytes=1052208"
    )
    assert log.count(signature) == 1
    assert "FAIL" not in log
    assert "FATAL" not in log


def test_cp7_input_manifest_matches_current_isolated_sources() -> None:
    lines = INPUTS.read_text(encoding="utf-8-sig").splitlines()
    metadata: dict[str, str] = {}
    include_dirs: list[str] = []
    records: list[tuple[str, str]] = []

    for line in lines:
        if line.startswith("sha256="):
            digest, relative = line.removeprefix("sha256=").split("|", 1)
            target = ROOT / relative
            target.resolve().relative_to(ROOT.resolve())
            assert target.is_file(), relative
            assert _sha256(target) == digest, relative
            records.append((digest, relative))
            continue
        key, separator, value = line.partition("=")
        assert separator, f"malformed input line: {line!r}"
        if key == "include_dir":
            assert (ROOT / value).is_dir()
            include_dirs.append(value)
        else:
            assert key not in metadata
            metadata[key] = value

    assert metadata["checkpoint"] == "CP7"
    assert metadata["scope"] == "registered_internal_fault_abort_connected_XSim"
    assert include_dirs == ["rtl", "imports/memory_v4"]
    assert len(records) == 27
    assert records[-1][1] == "scripts/run_cp7_registered_fault_xsim.ps1"
    assert any(
        relative == "rtl/sequential_v4_sparse_memory_subsystem.sv"
        for _, relative in records
    )
    assert any(
        relative == "tb/tb_sequential_v4_sparse_memory_subsystem.sv"
        for _, relative in records
    )


def test_cp7_evidence_bundle_is_complete() -> None:
    expected = {
        "cp7_registered_fault_xelab_console.txt",
        "cp7_registered_fault_xsim.log",
        "cp7_registered_fault_xsim_console.txt",
        "cp7_registered_fault_xsim_inputs.txt",
        "cp7_registered_fault_xsim_summary.txt",
        "cp7_registered_fault_xvlog_console.txt",
        "summary.md",
    }
    assert {path.name for path in REPORTS.iterdir() if path.is_file()} == expected
