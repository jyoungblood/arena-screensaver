#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode is required to build Are.na Screen Saver."
  echo "Install Xcode from the Mac App Store, then open it once."
  exit 1
fi

xcodebuild \
  -project "$project_root/ArenaScreenSaver.xcodeproj" \
  -scheme ArenaScreenSaver \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$project_root/build" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  build

echo "Built $project_root/build/Build/Products/Release/ArenaScreenSaver.saver"
