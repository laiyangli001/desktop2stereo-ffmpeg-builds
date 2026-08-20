#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

TARGET="${1:-Windows-amd64}"
if [[ "$TARGET" != "Windows-amd64" ]]; then
  echo "Unsupported Windows target: $TARGET" >&2
  exit 1
fi

WORK_ROOT="$REPO_ROOT/work/$TARGET"
SOURCE_ROOT="$WORK_ROOT/src"
PACKAGE_ROOT="$WORK_ROOT/package"
PREFIX="$PACKAGE_ROOT/ffmpeg"
DIST_ROOT="$REPO_ROOT/dist"

rm -rf "$WORK_ROOT" "$DIST_ROOT"
mkdir -p "$SOURCE_ROOT" "$PREFIX" "$DIST_ROOT"

clone_exact https://github.com/FFmpeg/FFmpeg.git \
  "$FFMPEG_REF" "$SOURCE_ROOT/ffmpeg" "$FFMPEG_FETCH_REF"
clone_exact https://git.videolan.org/git/ffmpeg/nv-codec-headers.git \
  "$NV_CODEC_HEADERS_REF" "$SOURCE_ROOT/nv-codec-headers" "$NV_CODEC_HEADERS_FETCH_REF"
clone_exact https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git \
  "$AMF_HEADERS_REF" "$SOURCE_ROOT/amf" "$AMF_HEADERS_FETCH_REF"
clone_exact https://github.com/KhronosGroup/Vulkan-Headers.git \
  "$VULKAN_HEADERS_REF" "$SOURCE_ROOT/vulkan-headers" "$VULKAN_HEADERS_FETCH_REF"

make -C "$SOURCE_ROOT/nv-codec-headers" PREFIX=/mingw64 install
mkdir -p /mingw64/include/AMF
cp -R "$SOURCE_ROOT/amf/amf/public/include/." /mingw64/include/AMF/
cp -R "$SOURCE_ROOT/vulkan-headers/include/." /mingw64/include/

export PKG_CONFIG_PATH="/mingw64/lib/pkgconfig:/mingw64/share/pkgconfig"
export PATH="/mingw64/bin:$PATH"

cd "$SOURCE_ROOT/ffmpeg"
CONFIGURE_ARGS=(
  "--prefix=$PREFIX"
  --enable-gpl
  --disable-nonfree
  --enable-shared
  --disable-static
  --disable-debug
  --disable-doc
  --disable-ffplay
  --enable-ffmpeg
  --enable-ffprobe
  --enable-libx264
  --enable-libx265
  --enable-libopus
  --enable-libsrt
  --enable-vulkan
  --enable-nvenc
  --enable-amf
  --enable-libvpl
  --extra-cflags=-I/mingw64/include
  --extra-ldflags=-L/mingw64/lib
)

./configure "${CONFIGURE_ARGS[@]}"
make -j"${NUMBER_OF_PROCESSORS:-4}"
make install

"$PREFIX/bin/ffmpeg.exe" -buildconf > "$PACKAGE_ROOT/configure.txt" 2>&1
prepare_package_metadata "$PACKAGE_ROOT" "$TARGET" "mingw64-gcc"
copy_ffmpeg_licenses "$SOURCE_ROOT/ffmpeg" "$PACKAGE_ROOT"

collect_mingw_dependencies() {
  local bin_dir="$1"
  local changed=1
  while [[ "$changed" -eq 1 ]]; do
    changed=0
    while IFS= read -r binary; do
      while IFS= read -r dependency; do
        [[ -f "$dependency" ]] || continue
        local destination="$bin_dir/$(basename "$dependency")"
        if [[ ! -f "$destination" ]]; then
          cp "$dependency" "$destination"
          changed=1
        fi
      done < <(
        ldd "$binary" 2>/dev/null | sed -nE \
          's|.*=> (/mingw64/bin/[^ ]+).*|\1|p; s|^[[:space:]]*(/mingw64/bin/[^ ]+).*|\1|p'
      )
    done < <(find "$bin_dir" -maxdepth 1 -type f \( -iname '*.exe' -o -iname '*.dll' \))
  done
}

collect_mingw_dependencies "$PREFIX/bin"

python "$REPO_ROOT/scripts/verify-runtime.py" "$PACKAGE_ROOT" "$TARGET"

ARCHIVE_BASE="$(archive_name "$TARGET")"
7z a -tzip -mx=9 "$DIST_ROOT/$ARCHIVE_BASE.zip" "$PACKAGE_ROOT/*"
sha256sum "$DIST_ROOT/$ARCHIVE_BASE.zip" > "$DIST_ROOT/$ARCHIVE_BASE.zip.sha256"

echo "Windows package created: $DIST_ROOT/$ARCHIVE_BASE.zip"
