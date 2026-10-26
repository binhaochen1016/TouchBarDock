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
# 优先使用固定证书（授权跨重编译有效），无证书时退回 ad-hoc（每次需重新授权辅助功能）
# 也可显式指定：SIGN_IDENTITY="证书名" ./Scripts/make_app.sh
if [ -z "${SIGN_IDENTITY:-}" ]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "TouchBarDockSign"; then
    SIGN_IDENTITY="TouchBarDockSign"
  else
    SIGN_IDENTITY="-"
  fi
fi
echo "  使用签名身份: $SIGN_IDENTITY"
codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "✅ 完成：$APP"
open "$APP"
