# dmgbuild settings for Switchr.dmg. Run through scripts/build-app.sh --dmg.
import os.path

app = defines.get("app", "build/Switchr.app")  # noqa: F821 (provided by dmgbuild)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "Assets/AppIcon.icns"
background = "Assets/dmg-background.tiff"

# The background is 660 x 480 pt; the extra height is the window title bar. Finder on
# macOS 26 adds a toolbar and status bar anyway, so the art keeps its content in the top 400 pt.
window_rect = ((240, 140), (660, 508))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = "auto"
arrange_by = None
label_pos = "bottom"
text_size = 13
icon_size = 104
icon_locations = {
    app_name: (170, 175),
    "Applications": (490, 175),
}
