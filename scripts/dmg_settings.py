# dmgbuild 的设置：安装盘打开时的样子。窗口背景是安装指引（Resources/install-guide/render.py 画的）。
# 由 scripts/make_dmg.sh 调用，app 和 background 从命令行传进来。
app = defines["app"]  # noqa: F821
files = [app]
symlinks = {"Applications": "/Applications"}
background = defines["background"]  # noqa: F821
format = "UDZO"
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
# 背景图 640×440，窗口再加上标题栏的高度
window_rect = ((240, 180), (640, 468))
icon_size = 96
text_size = 12
arrange_by = None
icon_locations = {"Brim.app": (180, 170), "Applications": (460, 170)}
