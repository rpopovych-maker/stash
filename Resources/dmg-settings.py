app = defines.get("app", "build/Stash.app")

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"
background = "Resources/dmg-background.tiff"

window_rect = ((200, 200), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True

icon_size = 112
text_size = 13
icon_locations = {
    "Stash.app": (165, 200),
    "Applications": (495, 200),
}
