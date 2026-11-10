#!/usr/bin/env python3
"""画安装指引：安装盘（DMG）窗口的背景图，和 README 里“第一次打开”的步骤图。
要 Pillow；字用系统自带的（冬青黑体、SF）。改了文案就重跑：python3 Resources/install-guide/render.py
颜色是 sniai 院子色的临时值。"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
ZH = "/System/Library/Fonts/Hiragino Sans GB.ttc"
EN = "/System/Library/Fonts/SFNS.ttf"
PAPER, BAND, INK, SOFT, LEAF, LASER = "#EAF1ED", "#7FA398", "#16302B", "#4E6A63", "#54B399", "#2257EE"

STEPS = [
    ("打开 brim，系统会拦下：点“完成”", "Open brim. macOS stops it: click Done"),
    ("系统设置 → 隐私与安全性，拉到最下面", "System Settings → Privacy & Security, scroll down"),
    ("在 brim 那一行点“仍要打开”，输入密码", "Next to brim, click Open Anyway, enter your password"),
]

def font(path, size, bold=False):
    f = ImageFont.truetype(path, size, index=1 if (bold and path == ZH) else 0)
    if path == EN:
        # SF 是可变字体：只动粗细，别的轴（宽度、视觉尺寸）用默认值
        axes = [a["default"] for a in f.get_variation_axes()]
        names = [a["name"] for a in f.get_variation_axes()]
        if "Weight" in names: axes[names.index("Weight")] = 650 if bold else 400
        f.set_variation_by_axes(axes)
    return f

def eave(d, x, y, u, color):
    """帽檐：一道屋檐，下面三个小方块（和菜单栏上的图标一个样子）"""
    for i in range(5):
        d.rectangle([x + (4 - i) * u, y + i * u, x + (5 - i) * u - 1, y + (i + 1) * u - 1], fill=color)
        d.rectangle([x + (5 + i) * u, y + i * u, x + (6 + i) * u - 1, y + (i + 1) * u - 1], fill=color)
    for k, c in zip((1.5, 4.5, 7.5), (LEAF, LASER, SOFT)):
        d.rectangle([x + k * u, y + 6.5 * u, x + (k + 1.4) * u, y + 7.9 * u], fill=c)

def steps(d, x, y, w, s, gap):
    for i, (zh, en) in enumerate(STEPS):
        yy = y + i * gap
        d.ellipse([x, yy, x + 22 * s, yy + 22 * s], fill=INK)
        n = font(EN, 13 * s, True)
        d.text((x + 11 * s, yy + 11 * s), str(i + 1), font=n, fill=PAPER, anchor="mm")
        d.text((x + 32 * s, yy - 1 * s), zh, font=font(ZH, 13 * s), fill=INK)
        d.text((x + 32 * s, yy + 17 * s), en, font=font(EN, 11 * s), fill=SOFT)

def dmg(s):
    """安装盘窗口 640×440：上面拖进“应用程序”，下面第一次打开怎么放行。图标由访达画在 (180,170) 和 (460,170)"""
    W, H = 640 * s, 440 * s
    im = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(im)
    # 图标那一条用中间调：访达在浅色、深色外观下图标名字分别是黑字、白字，都要看得清
    d.rectangle([0, 84 * s, W, 262 * s], fill=BAND)
    eave(d, 28 * s, 26 * s, 3 * s, INK)
    d.text((72 * s, 22 * s), "把 brim 拖进“应用程序”", font=font(ZH, 19 * s, True), fill=INK)
    d.text((72 * s, 50 * s), "Drag brim into Applications", font=font(EN, 13 * s), fill=SOFT)
    # 箭头
    y = 170 * s
    d.line([262 * s, y, 372 * s, y], fill=PAPER, width=3 * s)
    d.polygon([(372 * s, y - 9 * s), (390 * s, y), (372 * s, y + 9 * s)], fill=PAPER)
    d.text((28 * s, 280 * s), "第一次打开  ·  First launch", font=font(ZH, 12 * s, True), fill=SOFT)
    steps(d, 28 * s, 306 * s, W, s, 42 * s)
    return im

def readme(s=2):
    """README 用：第一次打开的三步"""
    W, H = 720 * s, 230 * s
    im = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(im)
    eave(d, 32 * s, 30 * s, 3 * s, INK)
    d.text((78 * s, 26 * s), "第一次打开 brim", font=font(ZH, 19 * s, True), fill=INK)
    d.text((78 * s, 54 * s), "Opening brim for the first time", font=font(EN, 13 * s), fill=SOFT)
    steps(d, 32 * s, 96 * s, W, s, 42 * s)
    return im

dmg(1).save(HERE / "dmg-background.png")
dmg(2).save(HERE / "dmg-background@2x.png")
readme().save(HERE / "first-launch.png")
print("好了")
