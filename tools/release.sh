#!/usr/bin/env bash
# One command for a Yandex Games upload: lint + tests + export (./build.sh), then a named copy
#   build/releases/bizarre-gems-<version>-<date>-<commit>.zip
# and the checks the Yandex console cares about (index.html at the archive root, size). Warns about uncommitted changes:
# they go into the build but not into the commit name.
set -euo pipefail
cd "$(dirname "$0")/.."
ver=$(sed -nE 's/^config\/version="([^"]+)"/\1/p' project.godot)
sha=$(git rev-parse --short HEAD)
dirty=""; git diff --quiet HEAD -- . ':!build' || { dirty="-dirty"; echo "release: uncommitted changes are included (name gets -dirty)" >&2; }
./build.sh
src=build/bizarre-gems-yandex.zip
unzip -Z1 "$src" | grep -qx index.html || { echo "release: index.html is not at the zip root" >&2; exit 1; }
size=$(stat -c %s "$src")
(( size < 100 * 1024 * 1024 )) || echo "release: archive is $((size / 1048576)) MB, check the Yandex size limit" >&2
mkdir -p build/releases
out=build/releases/bizarre-gems-$ver-$(date +%Y%m%d)-$sha$dirty.zip
cp "$src" "$out"
echo "release: $out ($((size / 1048576)) MB, $(unzip -Z1 "$src" | wc -l) files)"
echo "upload it in the Yandex Games console: Draft -> Build -> Upload archive"
