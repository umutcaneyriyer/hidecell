#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
# One-time setup: python3 -m venv .build/dmg-tools
# .build/dmg-tools/bin/pip install -r Packaging/requirements.txt
package_python="$PWD/.build/dmg-tools/bin/python3"
test -x "$package_python" || { echo 'Install Packaging/requirements.txt into .build/dmg-tools first.'; exit 1; }
package_version="1.5.$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Hidecell.app/Contents/Info.plist)"
package_output="${1:-$PWD/Installers/Hidecell-${package_version}.dmg}"
package_output="${package_output:A}"
mkdir -p "${package_output:h}"
codesign --verify --deep --strict Hidecell.app
xcrun swift -module-cache-path .build/ModuleCache Packaging/draw-background.swift Packaging/background@2x.png
sips -s format tiff Packaging/background@2x.png --out Packaging/background.tiff >/dev/null
sips --setProperty dpiWidth 144 --setProperty dpiHeight 144 Packaging/background.tiff >/dev/null
package_work=$(mktemp -d)
package_mount="$package_work/mount"
cleanup() {
 if [[ -d "$package_mount" ]]; then
  hdiutil detach "$package_mount" >/dev/null 2>&1 || return
 fi
 rm -rf "$package_work"
}
trap cleanup EXIT
hdiutil create -size 48m -fs HFS+ -volname Hidecell "$package_work/layout.dmg"
hdiutil attach "$package_work/layout.dmg" -mountpoint "$package_mount" -nobrowse
mkdir -p "$package_mount/.background"
ditto Hidecell.app "$package_mount/Hidecell.app"
ln -s /Applications "$package_mount/Applications"
cp Packaging/background.tiff "$package_mount/.background/background.tiff"
"$package_python" Packaging/layout.py "$package_mount"
hdiutil detach "$package_mount"
hdiutil convert "$package_work/layout.dmg" -format UDZO -o "$package_output" -ov
hdiutil verify "$package_output"
echo "Created: $package_output"
