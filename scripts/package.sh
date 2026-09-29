#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
source scripts/toolchain.sh
bash scripts/build.sh
mkdir -p dist
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' assets/Info.plist)
DMG="dist/DriftShelf-$VERSION-$ARCH.dmg"
STAGE=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
ditto "build/DriftShelf.app" "$STAGE/DriftShelf.app"
ln -s /Applications "$STAGE/Applications"
cp assets/安装说明.txt "$STAGE/Read Me - 说明.txt"
hdiutil create -volname "DriftShelf" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
echo "Ready: $DMG"
