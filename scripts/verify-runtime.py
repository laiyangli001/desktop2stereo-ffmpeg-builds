#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def run(executable: Path, *arguments: str) -> str:
    environment = os.environ.copy()
    bin_dir = str(executable.parent)
    environment["PATH"] = bin_dir + os.pathsep + environment.get("PATH", "")
    lib_dir = executable.parent.parent / "lib"
    if sys.platform.startswith("linux"):
        environment["LD_LIBRARY_PATH"] = str(lib_dir) + os.pathsep + environment.get(
            "LD_LIBRARY_PATH", ""
        )
    elif sys.platform == "darwin":
        environment["DYLD_LIBRARY_PATH"] = str(lib_dir) + os.pathsep + environment.get(
            "DYLD_LIBRARY_PATH", ""
        )
    completed = subprocess.run(
        [str(executable), "-hide_banner", *arguments],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=environment,
        timeout=30,
    )
    if completed.returncode != 0:
        fail(f"{' '.join(arguments)} failed with {completed.returncode}:\n{completed.stdout}")
    return completed.stdout


def has_word(output: str, value: str) -> bool:
    return re.search(rf"(?<![A-Za-z0-9_]){re.escape(value)}(?![A-Za-z0-9_])", output) is not None


def main() -> None:
    if len(sys.argv) != 3:
        fail("usage: verify-runtime.py PACKAGE_ROOT TARGET")
    package_root = Path(sys.argv[1]).resolve()
    target = sys.argv[2]
    repo_root = Path(__file__).resolve().parents[1]
    targets = json.loads((repo_root / "config" / "targets.json").read_text(encoding="utf-8"))[
        "targets"
    ]
    if target not in targets:
        fail(f"unknown target: {target}")

    executable_name = "ffmpeg.exe" if target.startswith("Windows-") else "ffmpeg"
    executable = package_root / "ffmpeg" / "bin" / executable_name
    if not executable.is_file():
        fail(f"FFmpeg executable is missing: {executable}")

    metadata = json.loads((package_root / "build-info.json").read_text(encoding="utf-8"))
    if metadata.get("nonfree") is not False:
        fail("build-info.json does not explicitly disable nonfree components")
    if metadata.get("license_profile") != "GPL":
        fail("expected GPL license profile for x264/x265 build")

    for required in (
        package_root / "configure.txt",
        package_root / "dependency-versions.txt",
        package_root / "SOURCE-OFFER.md",
        package_root / "licenses",
        package_root / "ffmpeg" / "include" / "libavcodec",
        package_root / "ffmpeg" / "include" / "libavutil",
        package_root / "ffmpeg" / "lib" / "pkgconfig",
    ):
        if not required.exists():
            fail(f"required SDK artifact is missing: {required}")

    version_output = run(executable, "-version")
    buildconf_output = run(executable, "-buildconf")
    encoders_output = run(executable, "-encoders")
    protocols_output = run(executable, "-protocols")

    expected_version = metadata["ffmpeg_version"]
    if not has_word(version_output, expected_version):
        fail(f"FFmpeg version does not contain {expected_version}")
    if "--enable-nonfree" in buildconf_output:
        fail("FFmpeg was configured with --enable-nonfree")

    definition = targets[target]
    missing_encoders = [
        name for name in definition["required_encoders"] if not has_word(encoders_output, name)
    ]
    missing_protocols = [
        name for name in definition["required_protocols"] if not has_word(protocols_output, name)
    ]
    if missing_encoders:
        fail(f"missing required encoders for {target}: {', '.join(missing_encoders)}")
    if missing_protocols:
        fail(f"missing required protocols for {target}: {', '.join(missing_protocols)}")

    print(f"Runtime verification passed: {target}")
    print(f"Required encoders: {', '.join(definition['required_encoders'])}")
    print(f"Required protocols: {', '.join(definition['required_protocols'])}")


if __name__ == "__main__":
    main()
