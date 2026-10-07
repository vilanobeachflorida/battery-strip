# Layout of Battery Strip's disk image window, for dmgbuild. scripts/release.sh passes:
#   -D app=<path to Battery Strip.app>
# Icon positions must match scripts/make-dmg-background.swift.
import os

app = defines["app"]
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
# No hide_extensions: the Finder flag it sets on the app fails `codesign --verify --strict`.

icon = os.path.join(app, "Contents/Resources/AppIcon.icns")
background = "Design/DMG/background.tiff"

# 400 points of background plus the title bar.
window_rect = ((200, 160), (640, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    app_name: (170, 190),
    "Applications": (470, 190),
}
