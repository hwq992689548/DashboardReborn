#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

export CLANG_MODULE_CACHE_PATH="$PWD/.build/modulecache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/modulecache"

swift build -c release --product Dashboard --scratch-path .build --cache-path .build/swiftpm-cache --disable-sandbox

APP="$PWD/dist/Dashboard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/Dashboard" "$APP/Contents/MacOS/Dashboard"
cp "Support/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/Dashboard"

# 本地原型用 ad-hoc 签名即可；正式分发请换 Developer ID 并做公证。
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "Built: $APP"
