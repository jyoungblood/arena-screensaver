#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
preview_build="$project_root/build-preview"
preview_app="$preview_build/Build/Products/Debug/ArenaPreview.app"

echo "Building Are.na Preview…"

if ! build_output="$(
  xcodebuild \
    -project "$project_root/ArenaScreenSaver.xcodeproj" \
    -scheme ArenaPreview \
    -configuration Debug \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$preview_build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_REQUIRED=NO \
    build 2>&1
)"; then
  print -r -- "$build_output"
  echo "The preview build failed."
  exit 1
fi

echo "Opening Are.na Preview…"
pkill -x ArenaPreview 2>/dev/null || true
open -n "$preview_app"
echo "The preview window is open."
