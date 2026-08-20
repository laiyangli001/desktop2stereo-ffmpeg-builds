#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/config/versions.env"

export SOURCE_DATE_EPOCH=1787241600
export TZ=UTC
export LC_ALL=C

clone_exact() {
  local url="$1"
  local ref="$2"
  local destination="$3"
  local fetch_ref="${4:-$ref}"

  git init -q "$destination"
  git -C "$destination" remote add origin "$url"
  git -C "$destination" fetch -q --depth 1 origin "$fetch_ref"
  git -C "$destination" checkout -q --detach FETCH_HEAD
  local actual
  actual="$(git -C "$destination" rev-parse HEAD)"
  if [[ "$actual" != "$ref" ]]; then
    echo "Source revision mismatch for $url: $actual != $ref" >&2
    exit 1
  fi
}

prepare_package_metadata() {
  local package_root="$1"
  local target="$2"
  local compiler="$3"

  mkdir -p "$package_root/licenses"
  cp "$REPO_ROOT/LICENSE" "$package_root/licenses/build-scripts-MIT.txt"
  cp "$REPO_ROOT/config/versions.env" "$package_root/dependency-versions.txt"
  cat > "$package_root/build-info.json" <<EOF
{
  "ffmpeg_version": "$FFMPEG_VERSION",
  "ffmpeg_ref": "$FFMPEG_REF",
  "build_revision": $BUILD_REVISION,
  "platform": "$target",
  "compiler": "$compiler",
  "license_profile": "GPL",
  "nonfree": false,
  "vulkan_headers_ref": "$VULKAN_HEADERS_REF",
  "nv_codec_headers_ref": "$NV_CODEC_HEADERS_REF",
  "amf_headers_ref": "$AMF_HEADERS_REF"
}
EOF
  cat > "$package_root/SOURCE-OFFER.md" <<EOF
# Corresponding source information

This FFmpeg package was built by Desktop2Stereo FFmpeg Builds.

- FFmpeg version: $FFMPEG_VERSION
- FFmpeg commit: $FFMPEG_REF
- Build revision: $BUILD_REVISION
- Build scripts: the GitHub Release tag containing this package
- Exact external header revisions: see dependency-versions.txt

The release must include or link to the exact corresponding FFmpeg source,
patches, configuration, and source information for statically or dynamically
included third-party libraries. This build uses the GPL configuration and does
not enable nonfree components.
EOF
}

copy_ffmpeg_licenses() {
  local source_root="$1"
  local package_root="$2"
  for name in COPYING.GPLv2 COPYING.GPLv3 COPYING.LGPLv2.1 COPYING.LGPLv3 LICENSE.md; do
    if [[ -f "$source_root/$name" ]]; then
      cp "$source_root/$name" "$package_root/licenses/FFmpeg-$name"
    fi
  done
}

archive_name() {
  local target="$1"
  local normalized
  normalized="$(tr '[:upper:]' '[:lower:]' <<<"$target")"
  printf 'd2s-ffmpeg-%s-d2s.%s-%s' "$FFMPEG_VERSION" "$BUILD_REVISION" "$normalized"
}
