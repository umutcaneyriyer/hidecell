#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
package_output="${1:-$PWD/Installers}"
mkdir -p "$package_output"
package_output="${package_output:A}"
codesign --verify --deep --strict Hidecell.app
package_stage=$(mktemp -d)
trap 'rm -rf "$package_stage"' EXIT
mkdir -p "$package_stage/root/Applications"
ditto Hidecell.app "$package_stage/root/Applications/Hidecell.app"
pkgbuild --analyze --root "$package_stage/root" "$package_stage/components.plist"
/usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$package_stage/components.plist"
pkgbuild --root "$package_stage/root" --component-plist "$package_stage/components.plist" --identifier app.hidecell.installer --version 1.5.10 --install-location / "$package_output/Hidecell-V1-Node-1.5.10-local.pkg"
