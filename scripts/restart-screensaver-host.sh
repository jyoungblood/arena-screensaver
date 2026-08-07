#!/bin/zsh
set -euo pipefail

pkill -x legacyScreenSaver 2>/dev/null || true
pkill -x legacyScreenSaver-x86_64 2>/dev/null || true
pkill -x ScreenSaverEngine 2>/dev/null || true

echo "Stopped the macOS screen-saver host processes."
