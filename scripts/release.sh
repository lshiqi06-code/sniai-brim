#!/bin/zsh
# 打发布包：编译、打包成 Brim.app、签名，压成 build/Brim-版本号.zip，写出 SHA-256。
# 有“Developer ID Application”证书、并设了 NOTARY_PROFILE（xcrun notarytool store-credentials 存的名字）时，
# 加上 hardened runtime、送去公证、把公证结果钉进 app，别人下载后能直接打开；
# 没有的话照旧用 Apple 开发证书签名，别人第一次打开要去“系统设置 › 隐私与安全性”点“仍要打开”。
# 用法：./scripts/release.sh
# 收费版借这个脚本打包：BRIM_PACKAGE、BRIM_PRODUCT 同 build_and_run.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
"$HERE/build_and_run.sh" --no-open
cd "${BRIM_PACKAGE:-$HERE/..}"
APP=build/Brim.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

DEVID=$(security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application[^"]*"' | tr -d '"' || true)
if [[ -n "$DEVID" && -n "${NOTARY_PROFILE:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVID" "$APP"
  ditto -c -k --keepParent "$APP" build/notarize.zip
  xcrun notarytool submit build/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f build/notarize.zip
  NOTE="已公证"
else
  NOTE="未公证：别人第一次打开要去“系统设置 › 隐私与安全性”点“仍要打开”"
fi

ZIP="build/Brim-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd build && shasum -a 256 "Brim-$VERSION.zip" > "Brim-$VERSION.zip.sha256")
echo "$ZIP（$NOTE）"
cat "$ZIP.sha256"
