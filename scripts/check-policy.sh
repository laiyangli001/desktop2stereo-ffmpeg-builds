#!/usr/bin/env bash
set -euo pipefail

if grep -R --fixed-strings -- '--enable-nonfree' scripts/build-*.sh config; then
  echo 'ERROR: public FFmpeg builds must not enable nonfree components' >&2
  exit 1
fi

echo 'Redistribution policy check passed: nonfree components are disabled.'
