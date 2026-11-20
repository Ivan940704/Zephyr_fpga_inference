#!/usr/bin/env python3
"""Program one matching overlay and run exactly one Stage 2 board smoke test."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
from typing import Dict

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from software.pynq.parameter_bram_bringup import (
    BringupError,
    CONTROL_BASE,
    CONTROL_BYTES,
    ParameterBramDriver,
    load_arm_dsb_sy,
    load_v3_contract,
)


BASELINE_COMMIT = "78c86f38f7c8f227bc2d032f5e2ef59ae4935d3e"
ARTIFACT_BASENAME = "parameter_bram_stage2"


class BoardPreflightError(BringupError):
    """The board must not be programmed because preflight is incomplete."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def emit(event: str, **fields) -> None:
    record = {"timestamp_utc": utc_now(), "event": event, **fields}
    print(json.dumps(record, sort_keys=True), flush=True)


def read_text_if_present(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace").strip()


def collect_board_environment(pynq_module) -> Dict[str, str]:
    model_path = Path("/sys/firmware/devicetree/base/model")
    model = ""
    if model_path.is_file():
        model = model_path.read_bytes().rstrip(b"\0").decode("utf-8", "replace")
    os_release = read_text_if_present(Path("/etc/os-release"))
    pynq_release = read_text_if_present(Path("/etc/pynq-release"))
    board_env = os.environ.get("BOARD", "")
    device_name = ""
    try:
        device_name = str(pynq_module.Device.active_device.name)
    except Exception:  # environment evidence remains useful without this field
        pass
    return {
        "board_environment": board_env,
        "device_tree_model": model,
        "pynq_release": pynq_release,
        "os_release": os_release,
        "linux_kernel": platform.release(),
        "machine": platform.machine(),
        "python_version": platform.python_version(),
        "pynq_version": str(getattr(pynq_module, "__version__", "UNKNOWN")),
        "pynq_device_name": device_name,
    }


def require_pynq_z1(environment: Dict[str, str]) -> None:
    identity_text = "\n".join(
        environment[key]
        for key in ("board_environment", "device_tree_model", "pynq_release")
    ).lower()
    normalized = identity_text.replace("_", "-").replace(" ", "-")
    if "pynq-z1" not in normalized:
        raise BoardPreflightError(
            "board identity does not explicitly identify PYNQ-Z1; refusing to program PL"
        )


def verify_artifact_manifest(
    manifest_path: Path, bit_path: Path, hwh_path: Path, ltx_path: Path
) -> Dict:
    if bit_path.stem != ARTIFACT_BASENAME or hwh_path.stem != ARTIFACT_BASENAME:
        raise BoardPreflightError("BIT and HWH must use the frozen matching basename")
    if ltx_path.stem != ARTIFACT_BASENAME:
        raise BoardPreflightError("LTX basename does not match BIT/HWH")
    if not (bit_path.parent.resolve() == hwh_path.parent.resolve() == ltx_path.parent.resolve()):
        raise BoardPreflightError("BIT, HWH, and LTX must be in the same directory")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema") != "zephyr.parameter_bram.stage2.artifacts.v1":
        raise BoardPreflightError("artifact manifest schema mismatch")
    if manifest.get("hardware_source_commit") != BASELINE_COMMIT:
        raise BoardPreflightError("artifact baseline commit mismatch")
    if manifest.get("artifact_basename") != ARTIFACT_BASENAME:
        raise BoardPreflightError("artifact manifest basename mismatch")
    target = manifest.get("target", {})
    if target.get("part") != "xc7z020clg400-1" or target.get("fclk0_mhz") != 100:
        raise BoardPreflightError("artifact part/clock contract mismatch")
    artifacts = manifest.get("artifacts", {})
    for path in (bit_path, hwh_path, ltx_path):
        expected = artifacts.get(path.name)
        if not expected:
            raise BoardPreflightError(f"artifact is absent from manifest: {path.name}")
        if path.stat().st_size != int(expected["bytes"]):
            raise BoardPreflightError(f"artifact byte count mismatch: {path.name}")
        if sha256_file(path) != expected["sha256"]:
            raise BoardPreflightError(f"artifact SHA-256 mismatch: {path.name}")
    return manifest


def compile_arm_barrier(destination: Path) -> Dict[str, str]:
    machine = platform.machine().lower()
    if not (machine.startswith("arm") or machine.startswith("aarch64")):
        raise BoardPreflightError(
            f"dsb sy helper may only be compiled on ARM, found {platform.machine()}"
        )
    compiler = shutil.which("cc") or shutil.which("gcc")
    if compiler is None:
        raise BoardPreflightError(
            "board has no existing C compiler for the required dsb sy helper"
        )
    source = Path(__file__).with_name("arm_barrier.c")
    if not source.is_file():
        raise BoardPreflightError(f"ARM barrier source is missing: {source}")
    completed = subprocess.run(
        [compiler, "-O2", "-fPIC", "-shared", "-o", str(destination), str(source)],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if completed.returncode != 0 or not destination.is_file():
        raise BoardPreflightError(
            "existing board compiler could not build the dsb sy helper: "
            + completed.stdout.strip()
        )
    version = subprocess.run(
        [compiler, "--version"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ).stdout.splitlines()
    return {
        "compiler": Path(compiler).name,
        "compiler_version": version[0] if version else "UNKNOWN",
        "library_sha256": sha256_file(destination),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bit", type=Path, required=True)
    parser.add_argument("--hwh", type=Path, required=True)
    parser.add_argument("--ltx", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--golden", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    evidence: Dict = {
        "schema": "zephyr.parameter_bram.stage2.board.v1",
        "checkpoint": "Stage 2 only",
        "started_utc": utc_now(),
        "conclusion": "BLOCKED",
        "overlay_program_attempted": False,
        "overlay_programmed": False,
    }
    driver = None
    try:
        for path in (
            args.bit,
            args.hwh,
            args.ltx,
            args.manifest,
            args.image,
            args.golden,
        ):
            if not path.is_file():
                raise BoardPreflightError(f"required input is missing: {path}")
        manifest = verify_artifact_manifest(
            args.manifest, args.bit, args.hwh, args.ltx
        )
        image, golden = load_v3_contract(args.image, args.golden)
        evidence["artifact_manifest_sha256"] = sha256_file(args.manifest)
        evidence["hardware_source_commit"] = manifest["hardware_source_commit"]
        evidence["image_preflight"] = {
            "bytes": len(image),
            "sha256": hashlib.sha256(image).hexdigest(),
            "magic_ascii": image[:7].decode("ascii"),
            "format_version": int.from_bytes(image[8:12], "little"),
            "stage2_vector_count": sum(
                vector["stage"] == 2
                for vector in golden["weight_readback_vectors"]["vectors"]
            ),
        }
        emit("local-artifact-preflight-pass")

        try:
            import pynq  # pylint: disable=import-outside-toplevel
            from pynq import Overlay  # pylint: disable=import-outside-toplevel
        except ImportError as error:
            raise BoardPreflightError(
                "PYNQ Python package is unavailable on the target environment"
            ) from error

        environment = collect_board_environment(pynq)
        evidence["board_environment"] = environment
        require_pynq_z1(environment)
        emit(
            "board-identity-pass",
            model=environment["device_tree_model"],
            pynq_version=environment["pynq_version"],
            kernel=environment["linux_kernel"],
        )

        with tempfile.TemporaryDirectory(prefix="zephyr_stage2_barrier_") as temp_dir:
            library_path = Path(temp_dir) / "libzephyr_arm_barrier.so"
            evidence["arm_barrier"] = compile_arm_barrier(library_path)
            barrier = load_arm_dsb_sy(library_path)
            emit("arm-dsb-sy-helper-pass", **evidence["arm_barrier"])

            overlay = Overlay(str(args.bit), download=False)
            evidence["overlay_program_attempted"] = True
            emit("overlay-download-start", volatile_only=True)
            overlay.download()
            evidence["overlay_programmed"] = True
            evidence["overlay_programmed_utc"] = utc_now()
            emit("overlay-download-pass", volatile_only=True)

            driver = ParameterBramDriver.from_pynq(barrier=barrier)
            stage2 = driver.run_stage2_smoke(args.image, args.golden)
            evidence["stage2"] = stage2
            evidence["conclusion"] = "STAGE 2 BOARD SMOKE PASS"
            emit(
                "stage2-board-smoke-pass",
                load_cycles=stage2["stage2"]["counters"]["load_cycles"],
                ar_bursts=stage2["stage2"]["counters"]["bursts"],
                r_beats=stage2["stage2"]["counters"]["beats"],
                readbacks=len(stage2["readbacks"]),
            )
            return 0
    except BoardPreflightError as error:
        evidence["conclusion"] = "BLOCKED"
        evidence["failure_type"] = type(error).__name__
        evidence["failure"] = str(error)
        emit("stage2-board-smoke-blocked", reason=str(error))
        return 2
    except Exception as error:  # board/program/load/readback failures are FAIL
        evidence["conclusion"] = "FAIL"
        evidence["failure_type"] = type(error).__name__
        evidence["failure"] = str(error)
        if driver is not None and driver.last_run_evidence is not None:
            evidence["stage2"] = driver.last_run_evidence
        emit("stage2-board-smoke-fail", reason=str(error))
        return 1
    finally:
        evidence["finished_utc"] = utc_now()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        print(evidence["conclusion"], flush=True)


if __name__ == "__main__":
    sys.exit(main())
