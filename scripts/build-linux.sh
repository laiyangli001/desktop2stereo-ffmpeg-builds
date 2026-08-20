#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

TARGET="${1:?target is required}"
case "$TARGET" in
  Linux-amd64|Linux-arm64) ;;
  *) echo "Unsupported Linux target: $TARGET" >&2; exit 1 ;;
esac

sudo apt-get update
APT_PACKAGES=(
  build-essential ca-certificates cmake git libopus-dev libsrt-openssl-dev
  libvulkan-dev libx264-dev libx265-dev nasm ninja-build patchelf pkg-config
  python3 xz-utils yasm
)
if [[ "$TARGET" == "Linux-amd64" ]]; then
  APT_PACKAGES+=(libvpl-dev)
fi
sudo apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"

WORK_ROOT="$REPO_ROOT/work/$TARGET"
SOURCE_ROOT="$WORK_ROOT/src"
PACKAGE_ROOT="$WORK_ROOT/package"
PREFIX="$PACKAGE_ROOT/ffmpeg"
DEPS_PREFIX="$WORK_ROOT/deps"
DIST_ROOT="$REPO_ROOT/dist"

rm -rf "$WORK_ROOT" "$DIST_ROOT"
mkdir -p "$SOURCE_ROOT" "$PREFIX" "$DEPS_PREFIX" "$DIST_ROOT"

clone_exact https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_REF" "$SOURCE_ROOT/ffmpeg"
clone_exact https://github.com/KhronosGroup/Vulkan-Headers.git \
  "$VULKAN_HEADERS_REF" "$SOURCE_ROOT/vulkan-headers" "$VULKAN_HEADERS_FETCH_REF"

cp -R "$SOURCE_ROOT/vulkan-headers/include/." "$DEPS_PREFIX/include/"
if [[ "$TARGET" == "Linux-amd64" ]]; then
  clone_exact https://git.videolan.org/git/ffmpeg/nv-codec-headers.git \
    "$NV_CODEC_HEADERS_REF" "$SOURCE_ROOT/nv-codec-headers" "$NV_CODEC_HEADERS_FETCH_REF"
  clone_exact https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git \
    "$AMF_HEADERS_REF" "$SOURCE_ROOT/amf" "$AMF_HEADERS_FETCH_REF"
  make -C "$SOURCE_ROOT/nv-codec-headers" PREFIX="$DEPS_PREFIX" install
  mkdir -p "$DEPS_PREFIX/include/AMF"
  cp -R "$SOURCE_ROOT/amf/amf/public/include/." "$DEPS_PREFIX/include/AMF/"
fi

export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:/usr/lib/$(gcc -dumpmachine)/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"

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
  "--extra-cflags=-I$DEPS_PREFIX/include"
  "--extra-ldflags=-L$DEPS_PREFIX/lib"
)
if [[ "$TARGET" == "Linux-amd64" ]]; then
  CONFIGURE_ARGS+=(--enable-nvenc --enable-amf --enable-libvpl)
fi

./configure "${CONFIGURE_ARGS[@]}"
make -j"$(nproc)"
make install

export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"
"$PREFIX/bin/ffmpeg" -buildconf > "$PACKAGE_ROOT/configure.txt" 2>&1
prepare_package_metadata "$PACKAGE_ROOT" "$TARGET" "$(gcc --version | head -n 1)"
copy_ffmpeg_licenses "$SOURCE_ROOT/ffmpeg" "$PACKAGE_ROOT"

collect_linux_dependencies() {
  local prefix="$1"
  local changed=1
  while [[ "$changed" -eq 1 ]]; do
    changed=0
    while IFS= read -r binary; do
      while IFS= read -r dependency; do
        [[ -f "$dependency" ]] || continue
        local base
        base="$(basename "$dependency")"
        case "$base" in
          linux-vdso*|ld-linux*|libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*)
            continue
            ;;
        esac
        if [[ ! -e "$prefix/lib/$base" ]]; then
          cp -L "$dependency" "$prefix/lib/$base"
          chmod u+w "$prefix/lib/$base"
          changed=1
        fi
      done < <(ldd "$binary" 2>/dev/null | awk '/=> \// {print $3} /^[[:space:]]*\// {print $1}')
    done < <(find "$prefix/bin" "$prefix/lib" -maxdepth 1 -type f -print)
  done
}

collect_linux_dependencies "$PREFIX"
patchelf --set-rpath '$ORIGIN/../lib' "$PREFIX/bin/ffmpeg" "$PREFIX/bin/ffprobe"
while IFS= read -r library; do
  patchelf --set-rpath '$ORIGIN' "$library" 2>/dev/null || true
done < <(find "$PREFIX/lib" -maxdepth 1 -type f -name '*.so*')

python3 "$REPO_ROOT/scripts/verify-runtime.py" "$PACKAGE_ROOT" "$TARGET"

ARCHIVE_BASE="$(archive_name "$TARGET")"
tar -C "$PACKAGE_ROOT" -cJf "$DIST_ROOT/$ARCHIVE_BASE.tar.xz" .
sha256sum "$DIST_ROOT/$ARCHIVE_BASE.tar.xz" > "$DIST_ROOT/$ARCHIVE_BASE.tar.xz.sha256"

echo "Linux package created: $DIST_ROOT/$ARCHIVE_BASE.tar.xz"
