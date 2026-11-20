#!/usr/bin/env python3
"""Build the portable native LayerNorm helper on the executing host."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path


class NativeBuildError(RuntimeError):
    """The local toolchain could not build the reviewed native helper."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build(source: Path, output: Path) -> dict[str, object]:
    compiler = shutil.which("cc") or shutil.which("gcc")
    if compiler is None:
        raise NativeBuildError("no existing C compiler was found")
    if not source.is_file():
        raise NativeBuildError(f"native LayerNorm source is missing: {source}")
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        compiler,
        "-O3",
        "-std=c11",
        "-fPIC",
        "-shared",
        "-o",
        str(output),
        str(source),
        "-lm",
    ]
    completed = subprocess.run(
        command,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if completed.returncode != 0 or not output.is_file():
        raise NativeBuildError(
            "native LayerNorm build failed: " + completed.stdout.strip()
        )
    version = subprocess.run(
        [compiler, "--version"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ).stdout.splitlines()
    result = {
        "compiler": Path(compiler).name,
        "compiler_version": version[0] if version else "UNKNOWN",
        "source_sha256": sha256_file(source),
        "library_sha256": sha256_file(output),
        "library_bytes": output.stat().st_size,
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source", type=Path, default=Path(__file__).with_name("native_layernorm.c")
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.output), sort_keys=True))


if __name__ == "__main__":
    main()
