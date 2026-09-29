#!/bin/bash
# Sourced by the build scripts; never changes the system-wide Xcode selection.
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "DriftShelf requires macOS 13 or later." >&2
    exit 1
fi
if ! xcrun --find swiftc >/dev/null 2>&1 || ! xcrun swiftc --version >/dev/null 2>&1; then
    if [[ -z "${DEVELOPER_DIR:-}" && -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]]; then
        export DEVELOPER_DIR=/Library/Developer/CommandLineTools
        echo "Using installed Xcode Command Line Tools."
    fi
fi
if ! xcrun swiftc --version >/dev/null 2>&1; then
    echo "Swift is unavailable. Install Apple's tools with: xcode-select --install" >&2
    echo "For full Xcode, open it once to complete setup and accept its license." >&2
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "Unsupported ARCH: $ARCH (use arm64 or x86_64)." >&2; exit 1 ;;
esac
