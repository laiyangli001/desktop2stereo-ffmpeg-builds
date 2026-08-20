#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

TARGET="${1:?target is required}"
case "$TARGET" in
  Darwin-amd64|Darwin-arm64) ;;
  *) echo "Unsupported macOS target: $TARGET" >&2; exit 1 ;;
esac

export HOMEBREW_NO_AUTO_UPDATE=1
brew install nasm opus pkg-config srt x264 x265 yasm

WORK_ROOT="$REPO_ROOT/work/$TARGET"
SOURCE_ROOT="$WORK_ROOT/src"
PACKAGE_ROOT="$WORK_ROOT/package"
PREFIX="$PACKAGE_ROOT/ffmpeg"
DIST_ROOT="$REPO_ROOT/dist"

rm -rf "$WORK_ROOT" "$DIST_ROOT"
mkdir -p "$SOURCE_ROOT" "$PREFIX" "$DIST_ROOT"

clone_exact https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_REF" "$SOURCE_ROOT/ffmpeg"

export PKG_CONFIG_PATH="$(brew --prefix x264)/lib/pkgconfig:$(brew --prefix x265)/lib/pkgconfig:$(brew --prefix opus)/lib/pkgconfig:$(brew --prefix srt)/lib/pkgconfig"
EXTRA_CPPFLAGS="-I$(brew --prefix x264)/include -I$(brew --prefix x265)/include -I$(brew --prefix opus)/include -I$(brew --prefix srt)/include"
EXTRA_LDFLAGS="-L$(brew --prefix x264)/lib -L$(brew --prefix x265)/lib -L$(brew --prefix opus)/lib -L$(brew --prefix srt)/lib"

cd "$SOURCE_ROOT/ffmpeg"
./configure \
  "--prefix=$PREFIX" \
  --enable-gpl \
  --disable-nonfree \
  --enable-shared \
  --disable-static \
  --disable-debug \
  --disable-doc \
  --disable-ffplay \
  --enable-ffmpeg \
  --enable-ffprobe \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libopus \
  --enable-libsrt \
  --enable-videotoolbox \
  --enable-audiotoolbox \
  "--extra-cflags=$EXTRA_CPPFLAGS" \
  "--extra-ldflags=$EXTRA_LDFLAGS"

make -j"$(sysctl -n hw.logicalcpu)"
make install

export DYLD_LIBRARY_PATH="$PREFIX/lib:${DYLD_LIBRARY_PATH:-}"
"$PREFIX/bin/ffmpeg" -buildconf > "$PACKAGE_ROOT/configure.txt" 2>&1
prepare_package_metadata "$PACKAGE_ROOT" "$TARGET" "$(clang --version | head -n 1)"
copy_ffmpeg_licenses "$SOURCE_ROOT/ffmpeg" "$PACKAGE_ROOT"

python3 "$REPO_ROOT/scripts/bundle-macos.py" "$PREFIX"
python3 "$REPO_ROOT/scripts/verify-runtime.py" "$PACKAGE_ROOT" "$TARGET"

ARCHIVE_BASE="$(archive_name "$TARGET")"
(cd "$PACKAGE_ROOT" && zip -qry "$DIST_ROOT/$ARCHIVE_BASE.zip" .)
shasum -a 256 "$DIST_ROOT/$ARCHIVE_BASE.zip" > "$DIST_ROOT/$ARCHIVE_BASE.zip.sha256"

echo "macOS package created: $DIST_ROOT/$ARCHIVE_BASE.zip"
