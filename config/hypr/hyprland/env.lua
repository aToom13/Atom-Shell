local vars = require("variables")
local home = os.getenv("HOME")

-- Themes
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("XCURSOR_THEME", vars.cursorTheme)
hl.env("XCURSOR_SIZE", vars.cursorSize)
hl.env("HYPRCURSOR_THEME", vars.cursorTheme)
hl.env("HYPRCURSOR_SIZE", vars.cursorSize)

-- Toolkit backends
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland,x11,windows")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- XDG specifications
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Turkish-locale user dirs (see ~/.config/user-dirs.dirs)
hl.env("XDG_PICTURES_DIR", home .. "/Resimler")
hl.env("XDG_VIDEOS_DIR", home .. "/Videolar")
hl.env("CAELESTIA_WALLPAPERS_DIR", home .. "/Resimler/Wallpapers")

-- Others
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
