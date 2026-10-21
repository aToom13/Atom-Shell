local vars = require("variables")
local fn   = require("hyprland.functions")

hl.on("hyprland.start", function()
    -- Keyring and auth
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Clipboard history
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Auto delete trash 30 days old
    hl.exec_cmd("trash-empty 30")

    -- Load exactly the plugins enabled in HyprPM.
    hl.exec_cmd("hyprpm reload -n")

    -- Cursors
    hl.exec_cmd("hyprctl setcursor " .. vars.cursorTheme .. " " .. vars.cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme " .. vars.cursorTheme)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. vars.cursorSize)

    -- Location provider and night light
    hl.exec_cmd("/usr/lib/geoclue-2.0/demos/agent")
    hl.exec_cmd("sleep 1 && gammastep")

    -- Forward bluetooth media commands to MPRIS
    hl.exec_cmd("mpris-proxy")

    -- KDE Connect background service (no application window)
    hl.exec_cmd("kdeconnectd")

    -- USB automount
    hl.exec_cmd("udiskie --no-notify")

    -- USB notification handler (udev + systemd user service)
    hl.exec_cmd("systemctl --user start atomshell-usb-notify.service || systemctl --user start usb-notify.service")

    -- Start shell
    hl.exec_cmd("atomshell start")

    -- Publish the graphical environment before starting D-Bus and user services.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP QT_QPA_PLATFORM && python3 ~/.config/quickshell/caelestia/utils/autostart.py session; systemctl --user start kdeconnect-tailscale.service")

    -- Auto-start music on its hidden special workspace.
    hl.exec_cmd("sleep 4 && exec env -u DISPLAY spotify --minimized", { workspace = "special:music silent" })

    -- Start window overview (qs-hyprview)
    hl.exec_cmd("qs -c qs-hyprview -n -d")
end)

-- Resizer listener
hl.on("window.title", function(win)
    local d = {
        hl.dsp.window.float({ action = "on", window = win }),
        hl.dsp.window.center({ window = win }),
    }
    local pip = fn.move_actions(win) or {}

    fn.resizer(win, "Bitwarden", 20, 54, d, true)
    fn.resizer(win, "Picture[- ]in[- ][Pp]icture", 0, 0, pip, false)
end)

hl.on("window.open", function(win)
    local d = {
        hl.dsp.window.float({ action = "on", window = win }),
        hl.dsp.window.center({ window = win }),
    }
    local pip = fn.move_actions(win) or {}

    fn.resizer(win, "Bitwarden", 20, 54, d, true)
    fn.resizer(win, "Picture[- ]in[- ][Pp]icture", 0, 0, pip, false)
end)
