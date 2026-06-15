#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CleanLock"
BUILD_DIR=".build"
DERIVED_DATA_DIR="$BUILD_DIR/XcodeDerivedData"
PRODUCT_APP="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

xcodebuild \
  -project CleanLock.xcodeproj \
  -scheme CleanLock \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  build

rm -rf "$APP_DIR"
cp -R "$PRODUCT_APP" "$APP_DIR"

echo "Built $APP_DIR"
