#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
source scripts/toolchain.sh
APP="build/DriftShelf.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp assets/Info.plist "$APP/Contents/Info.plist"
cp -R assets/en.lproj assets/zh-Hans.lproj "$APP/Contents/Resources/"
xcrun swiftc -sdk "$SDK_PATH" Sources/ShakeDetector.swift Tests/main.swift -o build/gesture-tests
build/gesture-tests
xcrun swiftc -sdk "$SDK_PATH" Sources/Localization.swift Tests/Localization/main.swift -o build/localization-tests
build/localization-tests "$APP"
xcrun swiftc -O -sdk "$SDK_PATH" -target "$ARCH-apple-macos13.0" -framework AppKit -framework UniformTypeIdentifiers Sources/Localization.swift Sources/ShakeDetector.swift Sources/main.swift -o "$APP/Contents/MacOS/DriftShelf"
cp assets/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP ($ARCH, macOS 13+, ad-hoc signature)"
echo "Run: open $APP"
