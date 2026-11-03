#!/bin/bash
# Builds a universal (Intel + Apple Silicon) KeyboardLock.app next to this script.
set -euo pipefail

cd "$(dirname "$0")"

APP="KeyboardLock.app"
BUILD="build"

rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD" "$APP/Contents/MacOS"

for ARCH in arm64 x86_64; do
    swiftc -O -swift-version 5 \
        -target "$ARCH-apple-macos11" \
        main.swift -o "$BUILD/KeyboardLock-$ARCH"
done

lipo -create "$BUILD/KeyboardLock-arm64" "$BUILD/KeyboardLock-x86_64" \
    -output "$APP/Contents/MacOS/KeyboardLock"
cp Info.plist "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/KeyboardLock"))"
