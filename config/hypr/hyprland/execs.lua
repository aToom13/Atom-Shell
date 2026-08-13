local vars = require("variables")
local fn   = require("hyprland.functions")

hl.on("hyprland.start", function()
    -- Keyring and auth
    hl.exec_cmd("sh -lc 'command -v gnome-keyring-daemon >/dev/null && exec gnome-keyring-daemon --start --components=secrets'")
    hl.exec_cmd("sh -lc 'for agent in /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 /usr/libexec/polkit-gnome-authentication-agent-1 /usr/lib/polkit-kde-authentication-agent-1; do [ -x \"$agent\" ] && exec \"$agent\"; done'")

    -- Clipboard history
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Auto delete trash 30 days old
    hl.exec_cmd("sh -lc 'command -v trash-empty >/dev/null && exec trash-empty 30'")

    -- Load exactly the plugins enabled in HyprPM.
    hl.exec_cmd("sh -lc 'command -v hyprpm >/dev/null && exec hyprpm reload -n'")

    -- Cursors
    hl.exec_cmd("hyprctl setcursor " .. vars.cursorTheme .. " " .. vars.cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme " .. vars.cursorTheme)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. vars.cursorSize)

    -- Location provider and night light
    hl.exec_cmd("sh -lc 'for agent in /usr/lib/geoclue-2.0/demos/agent /usr/libexec/geoclue-2.0/demos/agent; do [ -x \"$agent\" ] && exec \"$agent\"; done'")
    hl.exec_cmd("sh -lc 'command -v gammastep >/dev/null && sleep 1 && exec gammastep'")

    -- Forward bluetooth media commands to MPRIS
    hl.exec_cmd("sh -lc 'command -v mpris-proxy >/dev/null && exec mpris-proxy'")

    -- USB automount
    hl.exec_cmd("sh -lc 'command -v udiskie >/dev/null && exec udiskie --no-notify'")

    -- USB notification handler (udev + systemd user service)
    hl.exec_cmd("systemctl --user start atomshell-usb-notify.service")

    -- Start shell
    hl.exec_cmd("atomshell start")

    -- Start window overview (qs-hyprview)
    hl.exec_cmd("sh -lc 'command -v qs >/dev/null && [ -d \"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/qs-hyprview\" ] && exec qs -c qs-hyprview -n -d'")
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
