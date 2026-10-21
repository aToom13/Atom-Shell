local vars = require("variables")
local fn   = require("hyprland.functions")

-- Launcher
hl.bind("SUPER + SUPER_L", hl.dsp.global("caelestia:launcher"), { release = true })

-- Misc
hl.bind(vars.kbSession, hl.dsp.global("caelestia:session"))
hl.bind("ALT + F4", hl.dsp.global("caelestia:session"))
hl.bind(vars.kbShowSidebar, hl.dsp.global("caelestia:sidebar"))
hl.bind(vars.kbClearNotifs, hl.dsp.global("caelestia:clearNotifs"), { locked = true })
hl.bind(vars.kbShowPanels, hl.dsp.global("caelestia:showall"))
hl.bind(vars.kbLock, hl.dsp.global("caelestia:lock"))

-- ThinkPad icon keys; ordinary F7-F12 remain available to applications.
hl.bind("XF86Display", hl.dsp.exec_cmd("atomshell ipc call nexus togglePage 1"))
hl.bind("XF86NotificationCenter", hl.dsp.global("caelestia:sidebar"))
hl.bind("XF86PickupPhone", hl.dsp.exec_cmd("python3 " .. os.getenv("HOME") .. "/.config/hypr/scripts/desktop-assist.py stt"))
hl.bind("XF86HangupPhone", hl.dsp.exec_cmd("atomshell ipc call picker openText"))
hl.bind("XF86Favorites", hl.dsp.global("caelestia:help"))

-- Restore lock
hl.bind(vars.kbRestoreLock, function()
    hl.dispatch(hl.dsp.exec_cmd("atomshell start"))
    hl.dispatch(hl.dsp.global("caelestia:lock"))
end)

-- Brightness
hl.bind("XF86MonBrightnessUp", hl.dsp.global("caelestia:brightnessUp"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.global("caelestia:brightnessDown"), { locked = true })

-- Media
hl.bind("CTRL + SUPER + Space", hl.dsp.global("caelestia:mediaToggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.global("caelestia:mediaToggle"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.global("caelestia:mediaToggle"), { locked = true })
hl.bind("CTRL + SUPER + Page_Down", hl.dsp.global("caelestia:mediaNext"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.global("caelestia:mediaNext"), { locked = true })
hl.bind("CTRL + SUPER + Page_Up", hl.dsp.global("caelestia:mediaPrev"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.global("caelestia:mediaPrev"), { locked = true })
hl.bind("XF86AudioStop", hl.dsp.global("caelestia:mediaStop"), { locked = true })

-- Kill/restart
hl.bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd("atomshell stop"), { release = true })
hl.bind(
    "CTRL + SUPER + ALT + R",
    hl.dsp.exec_cmd("atomshell restart"),
    { release = true }
)

for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(vars.kbGoToWs .. " + " .. key, fn.wsaction("focus", "", i))
    hl.bind(vars.kbMoveWinToWs .. " + " .. key, fn.wsaction("move", "", i))
    hl.bind(vars.kbGoToWsGroup .. " + " .. key, fn.wsaction("focus", "group", i))
    hl.bind(vars.kbMoveWinToWsGroup .. " + " .. key, fn.wsaction("move", "group", i))
end

-- Go to workspace -1/+1
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "-1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "+1" }))
hl.bind(vars.kbPrevWs, hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind(vars.kbNextWs, hl.dsp.focus({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + Page_Up", hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + Page_down", hl.dsp.focus({ workspace = "+1" }), { repeating = true })

-- Go to workspace group -1/+1
hl.bind("CTRL + SUPER + mouse_down", hl.dsp.focus({ workspace = "-10" }))
hl.bind("CTRL + SUPER + mouse_up", hl.dsp.focus({ workspace = "+10" }))

-- Move window to workspace -1/+1
hl.bind("SUPER + ALT + Page_Up", hl.dsp.window.move({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + ALT + Page_Down", hl.dsp.window.move({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + ALT + mouse_down", hl.dsp.window.move({ workspace = "-1" }))
hl.bind("SUPER + ALT + mouse_up", hl.dsp.window.move({ workspace = "+1" }))
hl.bind("CTRL + SUPER + SHIFT + right", hl.dsp.window.move({ workspace = "+1" }), { repeating = true })
hl.bind("CTRL + SUPER + SHIFT + left", hl.dsp.window.move({ workspace = "-1" }), { repeating = true })

-- Move window to/from special workspace
hl.bind("CTRL + SUPER + SHIFT + up", hl.dsp.window.move({ workspace = "special:special" }))
hl.bind("CTRL + SUPER + SHIFT + down", hl.dsp.window.move({ workspace = "e+0" }))
hl.bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:special" }))

-- Window groups
hl.bind(vars.kbWindowGroupCycleNext, hl.dsp.window.cycle_next(), { repeating = true })
hl.bind(vars.kbWindowGroupCyclePrev, hl.dsp.window.cycle_next({ next = false }), { repeating = true })
hl.bind("CTRL + ALT + Tab", hl.dsp.group.next(), { repeating = true })
hl.bind("CTRL + SHIFT + ALT + Tab", hl.dsp.group.prev(), { repeating = true })
hl.bind(vars.kbToggleGroup, hl.dsp.group.toggle())
hl.bind(vars.kbUngroup, hl.dsp.window.move({ out_of_group = true }))
hl.bind("SUPER + SHIFT + B", hl.dsp.group.lock_active())

-- Window actions
hl.bind("SUPER + left", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + right", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + up", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + down", hl.dsp.focus({ direction = "down" }))
local captureWindowKeys = {}
table.insert(captureWindowKeys, hl.bind("SUPER + SHIFT + left", hl.dsp.window.move({ direction = "left" })))
table.insert(captureWindowKeys, hl.bind("SUPER + SHIFT + right", hl.dsp.window.move({ direction = "right" })))
table.insert(captureWindowKeys, hl.bind("SUPER + SHIFT + up", hl.dsp.window.move({ direction = "up" })))
table.insert(captureWindowKeys, hl.bind("SUPER + SHIFT + down", hl.dsp.window.move({ direction = "down" })))
table.insert(captureWindowKeys, hl.bind("SUPER + ALT + left", fn.resize_active_window(-10, 0), { repeating = true }))
table.insert(captureWindowKeys, hl.bind("SUPER + ALT + right", fn.resize_active_window(10, 0), { repeating = true }))
table.insert(captureWindowKeys, hl.bind("SUPER + ALT + up", fn.resize_active_window(0, -10), { repeating = true }))
table.insert(captureWindowKeys, hl.bind("SUPER + ALT + down", fn.resize_active_window(0, 10), { repeating = true }))

-- Lease restores desktop arrows even if the capture shell crashes.
local captureLease = hl.timer(function()
    for _, binding in ipairs(captureWindowKeys) do binding:set_enabled(true) end
end, { timeout = 2000, type = "oneshot" })
captureLease:set_enabled(false)
_G.caelestiaCaptureKeys = function(active)
    for _, binding in ipairs(captureWindowKeys) do binding:set_enabled(not active) end
    captureLease:set_enabled(false)
    captureLease:set_timeout(2000)
    captureLease:set_enabled(active)
end

hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(vars.kbMoveWindow, hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(vars.kbResizeWindow, hl.dsp.window.resize(), { mouse = true })
hl.bind("CTRL + SUPER + O", hl.dsp.window.center())
hl.bind("CTRL + SUPER + ALT + O", function()
    hl.dispatch(hl.dsp.window.resize(fn.resize_by_screen(55, 70)))
    hl.dispatch(hl.dsp.window.center())
end)
hl.bind(vars.kbWindowPip, function()
    local a = hl.get_active_window()
    if a then
        local pip = fn.move_actions(a) or {}
        if not a.floating then table.insert(pip, 1, hl.dsp.window.float()) end
        table.insert(pip, hl.dsp.window.pin({ action = "on", window = "address:" .. a.address }))

        for _, x in ipairs(pip) do
            hl.dispatch(x)
        end
    end
end)
hl.bind(vars.kbPinWindow, hl.dsp.window.pin())
hl.bind(vars.kbWindowFullscreen, hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(vars.kbWindowBorderedFullscreen, hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(vars.kbToggleWindowFloating, hl.dsp.window.float())
hl.bind(vars.kbCloseWindow, hl.dsp.window.close())

-- Special workspace toggles
hl.bind(vars.kbSpecialWs, hl.dsp.exec_cmd("caelestia toggle specialws"))
hl.bind(vars.kbSystemMonitorWs, hl.dsp.exec_cmd("caelestia toggle sysmon"))
hl.bind(vars.kbMusicWs, hl.dsp.exec_cmd("caelestia toggle music"))
hl.bind(vars.kbCommunicationWs, hl.dsp.exec_cmd("pgrep -f '[/]usr/lib/equibop/app.asar' >/dev/null || equibop --start-minimized & caelestia toggle communication"))
hl.bind(vars.kbTodoWs, hl.dsp.exec_cmd("caelestia toggle todo"))
hl.bind(vars.kbGamesWs, function()
    hl.exec_cmd("pgrep -x steam >/dev/null || exec " .. home .. "/.local/bin/steam-sw -silent", { workspace = "special:games silent" })
    hl.exec_cmd("caelestia toggle games")
end)

-- Apps
hl.bind(vars.kbTerminal, hl.dsp.exec_cmd(vars.terminal))
hl.bind(vars.kbBrowser, hl.dsp.exec_cmd(vars.browser))
hl.bind(vars.kbEditor, hl.dsp.exec_cmd(vars.editor))
hl.bind(vars.kbFileExplorer, hl.dsp.exec_cmd(vars.fileExplorer))
hl.bind("CTRL + ALT + V", hl.dsp.exec_cmd(vars.audioSettings))

-- Help / Shortcuts reference
hl.bind("SUPER + SHIFT + H", hl.dsp.global("caelestia:help"))

-- Window overview (qs-hyprview)
hl.bind("SUPER + Tab", hl.dsp.exec_cmd("qs ipc -c qs-hyprview call expose toggle smartgrid"))

-- Utilities
hl.bind("Print", hl.dsp.global("caelestia:screenshotFreeze"))
hl.bind("SUPER + SHIFT + S", hl.dsp.global("caelestia:screenshotFreeze"))
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"))

-- Volume
-- A short lease keeps plain Tab available if the shell exits or reloads.
local audioTab = hl.bind("Tab", function()
    hl.exec_cmd("qs -c caelestia ipc call audio openMixer")
end)
audioTab:set_enabled(false)
_G.caelestiaAudioMixerActive = false
local audioLease = hl.timer(function()
    audioTab:set_enabled(false)
    _G.caelestiaAudioMixerActive = false
end, { timeout = 2000, type = "oneshot" })
audioLease:set_enabled(false)
_G.caelestiaAudioKeys = function(mode)
    audioTab:set_enabled(mode == "armed")
    _G.caelestiaAudioMixerActive = mode == "mixer"
    audioLease:set_enabled(false)
    audioLease:set_timeout(2000)
    audioLease:set_enabled(mode ~= "off")
end

local function audioVolume(direction)
    if _G.caelestiaAudioMixerActive then
        hl.exec_cmd("qs -c caelestia ipc call audio adjustMixer " .. direction)
    else
        hl.dispatch(hl.dsp.exec_cmd(direction > 0
            and ("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l " .. (vars.volumeMax / 100) .. " @DEFAULT_AUDIO_SINK@ " .. vars.volumeStep .. "%+")
            or ("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ " .. vars.volumeStep .. "%-")))
        hl.exec_cmd("qs -c caelestia ipc call audio showOsd")
    end
end
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioMute", function()
    if _G.caelestiaAudioMixerActive then
        hl.exec_cmd("qs -c caelestia ipc call audio muteMixer")
    else
        hl.dispatch(hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
        hl.exec_cmd("qs -c caelestia ipc call audio showOsd")
    end
end, { locked = true })
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind(
    "XF86AudioRaiseVolume",
    function() audioVolume(1) end,
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioLowerVolume",
    function() audioVolume(-1) end,
    { locked = true, repeating = true }
)

-- Sleep
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd(vars.sleepGestureCmd), { locked = true })

-- Clipboard and emoji picker
hl.bind("SUPER + V", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard"))
hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard -d"))
hl.bind("SUPER + Period", hl.dsp.exec_cmd("pkill fuzzel || caelestia emoji -p"))
hl.bind(
    "CTRL + SHIFT + ALT + V",
    hl.dsp.exec_cmd('sleep 0.5s && ydotool type -d 1 "$(cliphist list | head -1 | cliphist decode)"'),
    { locked = true }
)

-- Testing
hl.bind(
    "SUPER + ALT + F12",
    hl.dsp.exec_cmd(
        "notify-send -u low -i dialog-information-symbolic 'Test notification' " ..
        [["Here's a really long message to test truncation and wrapping\nYou can middle click or flick this notification to dismiss it!"]] ..
        " -a 'Shell' -A 'Test1=I got it!' -A 'Test2=Another action'"
    )
)
