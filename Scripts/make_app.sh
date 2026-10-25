#!/bin/bash
# 构建 TouchBarDock.app（无 Dock 图标的菜单栏应用）
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ 编译（release）..."
swift build -c release --disable-sandbox

APP="build/TouchBarDock.app"
echo "▸ 组装 $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/TouchBarDock" "$APP/Contents/MacOS/TouchBarDock"
cp "Scripts/Info.plist" "$APP/Contents/Info.plist"

echo "▸ 签名..."
# 有自签名证书时用：SIGN_IDENTITY="证书名" ./Scripts/make_app.sh
# 证书固定后辅助功能授权跨重编译有效；默认 ad-hoc 签名每次重编译需重新授权
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "✅ 完成：$APP"
open "$APP"
