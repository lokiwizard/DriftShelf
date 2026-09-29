#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
source scripts/toolchain.sh
xcrun swiftc -sdk "$SDK_PATH" scripts/make-icon.swift -o build/make-icon
build/make-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o assets/AppIcon.icns
echo "Updated: assets/AppIcon.icns"
