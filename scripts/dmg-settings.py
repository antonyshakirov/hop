# dmgbuild settings: .DS_Store is written programmatically, without Finder —
# the layout is guaranteed to land in the image (the AppleScript path lost it).
import os.path

app = defines.get("app", "dist/Hop.app")  # noqa: F821

format = defines.get("format", "UDZO")  # noqa: F821
size = "60M"
files = [app]
symlinks = {"Applications": "/Applications"}

icon = "assets/AppIcon.icns"  # volume icon

background = "dist/dmg-bg.png"
window_rect = ((200, 160), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 185),
    "Applications": (470, 185),
}
