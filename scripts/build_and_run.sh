#!/bin/zsh
# 编译 brim、打包成 build/Brim.app、本机签名，装进 /Applications 再打开。
# 藏菜单栏图标要 brim 装在“应用程序”文件夹里（从 build/ 打开时系统认不出帽檐是谁的，会把它一起藏掉）。
# 用法：./scripts/build_and_run.sh          编译、安装并打开
#       ./scripts/build_and_run.sh --no-open 只编译打包，不安装
# 收费版借这个脚本打包：BRIM_PACKAGE 指向收费版的包，BRIM_PRODUCT=BrimPro（见收费版的 scripts/build_and_run.sh）
set -euo pipefail
RES="$(cd "$(dirname "$0")/.." && pwd)/Resources"
cd "${BRIM_PACKAGE:-$(dirname "$0")/..}"
PRODUCT="${BRIM_PRODUCT:-Brim}"

swift build -c release --product "$PRODUCT"
APP=build/Brim.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/$PRODUCT" "$APP/Contents/MacOS/Brim"
# 去掉调试符号：里面记着编译时的本机路径，会露出用户名和目录
strip -S -x "$APP/Contents/MacOS/Brim"
cp "$RES/Info.plist" "$APP/Contents/Info.plist"
cp "$RES/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# 只装在自己电脑上，不花钱。有 Apple 开发证书（免费的 Personal Team 也有）就用它签：
# 这样“辅助功能”授权一次就一直有效；用临时签名（-）的话每次重新编译都要重新授权。
# 钥匙串里有好几张证书时，用 BRIM_SIGN_IDENTITY 指定用哪张（证书的全名），发布包靠它选开发专用的那张。
IDENTITY="${BRIM_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"' || true)}"
codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
echo "签名：${IDENTITY:-本机临时签名}"

if [[ "${1:-}" != "--no-open" ]]; then
  pkill -x Brim 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Brim.app
  ditto "$APP" /Applications/Brim.app
  open /Applications/Brim.app
  echo "已安装并打开 /Applications/Brim.app"
fi
