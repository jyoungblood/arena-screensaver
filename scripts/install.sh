#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
source_saver="$project_root/build/Build/Products/Release/ArenaScreenSaver.saver"
install_directory="$HOME/Library/Screen Savers"
installed_saver="$install_directory/ArenaScreenSaver.saver"

"$project_root/scripts/build.sh"

mkdir -p "$install_directory"
ditto "$source_saver" "$installed_saver"
codesign --force --sign - "$installed_saver"
"$project_root/scripts/restart-screensaver-host.sh"

echo "Installed $installed_saver"
echo "Open System Settings → Screen Saver, then select Are.na under Other."
