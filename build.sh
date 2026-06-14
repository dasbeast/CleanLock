#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WipeLock"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$MODULE_CACHE_DIR"

cp Resources/Info.plist "$CONTENTS_DIR/Info.plist"

swiftc \
  -Xcc -fmodules-cache-path="$MODULE_CACHE_DIR" \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework ApplicationServices \
  -framework IOKit \
  Sources/WipeLock/main.swift \
  -o "$MACOS_DIR/$APP_NAME"

codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
