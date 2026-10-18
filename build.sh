#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build Hidecell.app/Contents/MacOS Hidecell.app/Contents/Resources
xcrun clang -fobjc-arc -c Sources/STMenuBarShim.m -o .build/shim.o
xcrun swiftc -module-cache-path .build/ModuleCache -swift-version 5 -O -import-objc-header Sources/include/STMenuBarShim.h Sources/Core.swift Sources/NativeVisibility.swift Sources/MenuLayout.swift Sources/main.swift .build/shim.o -framework AppKit -framework SwiftUI -framework ServiceManagement -o Hidecell.app/Contents/MacOS/Hidecell
cp Hidecell.icns Hidecell.app/Contents/Resources/Hidecell-Fold-v2.icns
cp Info.plist Hidecell.app/Contents/Info.plist
cp THIRD-PARTY-LICENSE.txt Hidecell.app/Contents/Resources/
cp Fonts/InstrumentSerif-Regular.ttf Hidecell.app/Contents/Resources/
cp Fonts/OFL.txt Hidecell.app/Contents/Resources/InstrumentSerif-LICENSE.txt
cp Fonts/Inter-Regular.ttf Hidecell.app/Contents/Resources/
cp Fonts/Inter-LICENSE.txt Hidecell.app/Contents/Resources/
python3 sign.py
echo "Built: $PWD/Hidecell.app"
