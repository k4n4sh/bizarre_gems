#!/usr/bin/env bash
# Build the Yandex Games upload: build/bizarre-gems-yandex.zip (index.html at the zip root).
set -euo pipefail
cd "$(dirname "$0")"
GODOT=${GODOT:-godot}
tools/lint.sh
rm -rf build/web && mkdir -p build/web
"$GODOT" --headless --audio-driver Dummy --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --audio-driver Dummy --path . --script res://tests/test_logic.gd
"$GODOT" --headless --audio-driver Dummy --path . --script res://tests/smoke_ui.gd 2>&1 | tee /dev/stderr | { ! grep -qE "FAIL|SCRIPT ERROR"; }
"$GODOT" --headless --audio-driver Dummy --path . --export-release "Yandex Web" build/web/index.html
rm -f build/bizarre-gems-yandex.zip
(cd build/web && zip -qr9 ../bizarre-gems-yandex.zip .)
ls -lh build/bizarre-gems-yandex.zip
