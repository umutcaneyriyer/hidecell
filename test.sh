#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build
xcrun swiftc -module-cache-path .build/ModuleCache Sources/Core.swift Sources/NativeVisibility.swift Tests/main.swift -o .build/HidecellTests
.build/HidecellTests
