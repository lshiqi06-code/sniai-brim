#!/bin/zsh
# 把 build/Brim.app 做成安装盘 build/Brim-版本号.dmg：打开就是一张安装指引
# （把 brim 拖进“应用程序”；第一次打开被系统拦下时怎么放行）。
# 用 dmgbuild（MIT）排窗口，不用操作访达。第一次用会把它装进 build/.dmg-venv（要联网，只装在这个文件夹里）。
# 用法：./scripts/make_dmg.sh        （先跑过 build_and_run.sh --no-open 或 release.sh）
# 收费版借这个脚本：BRIM_PACKAGE 同 build_and_run.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GUIDE="$HERE/../Resources/install-guide"
cd "${BRIM_PACKAGE:-$HERE/..}"
APP=build/Brim.app
[[ -d "$APP" ]] || { echo "✗ 没有 $APP，先打包" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
VENV=build/.dmg-venv
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet dmgbuild
fi
# 普通屏和视网膜屏各一张，合成一个文件
tiffutil -cathidpicheck "$GUIDE/dmg-background.png" "$GUIDE/dmg-background@2x.png" -out build/dmg-background.tiff >/dev/null 2>&1
DMG="build/Brim-$VERSION.dmg"
rm -f "$DMG"
"$VENV/bin/dmgbuild" -s "$HERE/dmg_settings.py" -D app="$APP" -D background=build/dmg-background.tiff "sniai brim" "$DMG" >/dev/null
rm -f build/dmg-background.tiff
(cd build && shasum -a 256 "Brim-$VERSION.dmg" > "Brim-$VERSION.dmg.sha256")
echo "$DMG"
cat "$DMG.sha256"
