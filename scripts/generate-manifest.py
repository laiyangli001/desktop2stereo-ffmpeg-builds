#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re


TARGET_SUFFIXES = {
    "windows-amd64": ("Windows-amd64", "ffmpeg/bin/ffmpeg.exe"),
    "linux-amd64": ("Linux-amd64", "ffmpeg/bin/ffmpeg"),
    "linux-arm64": ("Linux-arm64", "ffmpeg/bin/ffmpeg"),
    "darwin-amd64": ("Darwin-amd64", "ffmpeg/bin/ffmpeg"),
    "darwin-arm64": ("Darwin-arm64", "ffmpeg/bin/ffmpeg"),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()

    versions: dict[str, str] = {}
    for line in (Path(__file__).resolve().parents[1] / "config" / "versions.env").read_text(
        encoding="utf-8"
    ).splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            versions[key.strip()] = value.strip()

    targets: dict[str, dict[str, object]] = {}
    archives = sorted(
        path
        for path in args.assets.iterdir()
        if path.is_file() and (path.name.endswith(".zip") or path.name.endswith(".tar.xz"))
    )
    for archive in archives:
        lower_name = archive.name.lower()
        matched = next((item for suffix, item in TARGET_SUFFIXES.items() if suffix in lower_name), None)
        if matched is None:
            continue
        target, executable = matched
        targets[target] = {
            "ffmpeg_url": (
                f"https://github.com/{args.repository}/releases/download/{args.tag}/{archive.name}"
            ),
            "ffmpeg_sha256": sha256(archive),
            "ffmpeg_executable": executable,
        }

    manifest = {
        "schema_version": 2,
        "ffmpeg": {
            "version": versions["FFMPEG_VERSION"],
            "commit": versions["FFMPEG_REF"],
            "build_revision": int(versions["BUILD_REVISION"]),
            "release_tag": args.tag,
            "license_profile": "GPL",
            "nonfree": False,
        },
        "runtimes": targets,
    }
    output = args.assets / "runtime-manifest.json"
    output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
