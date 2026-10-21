local home   = os.getenv("HOME")
local hypr   = home .. "/.config/hypr"
package.path = package.path .. ";" .. home .. "/.config/caelestia/?.lua"

-- HyprPM only needs plugin permission; granting it here prevents a prompt on
-- every login while keeping all other compositor permissions untouched.
hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")

-- Create a file if it doesn't exist, optionally with initial content
local function maybe_create(file, content)
    local f = io.open(file)

    if f then
        f:close()
        return
    end

    f = io.open(file, "w")
    if f then
        if content then f:write(content) end
        f:close()
    end
end

-- Copy src to dst, but only if dst doesn't already exist
local function maybe_copy(src, dst)
    local out = io.open(dst)
    if out then
        out:close()
        return
    end

    local input = io.open(src, "r")
    if not input then return end

    out = io.open(dst, "w")
    if out then
        out:write(input:read("*a"))
        out:close()
    end
    input:close()
end

-- Maybe set current colours to defaults
maybe_copy(hypr .. "/scheme/default.lua", hypr .. "/scheme/current.lua")

-- User variables
maybe_create(home .. "/.config/caelestia/hypr-vars.lua", "return {}\n")
local overrides = require("hypr-vars")
if type(overrides) == "table" then
    local vars = require("variables")
    for k, v in pairs(overrides) do
        vars[k] = v
    end
end

-- Default monitor conf
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- Persistent per-output overrides written by Nexus > Display.  A plain TSV
-- keeps the settings inspectable and avoids coupling the UI to Lua syntax.
local monitor_overrides = home .. "/.config/caelestia/monitor-overrides.tsv"
local monitor_file = io.open(monitor_overrides, "r")
if monitor_file then
    for line in monitor_file:lines() do
        local output, mode, position, scale, transform, enabled, mirror = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t?([^\t]*)\t?([^\t]*)$")
        if output then
            hl.monitor({
                output    = output,
                mode      = mode,
                position  = position,
                scale     = tonumber(scale) or 1,
                transform = tonumber(transform) or 0,
                disabled  = enabled == "0",
                mirror    = mirror ~= "" and mirror or nil,
            })
        end
    end
    monitor_file:close()
end

-- Configs
local keybind_editor = require("keybind-editor")
keybind_editor.start()
require("hyprland.env")
require("hyprland.general")
require("hyprland.input")
require("hyprland.misc")
require("hyprland.animations")
require("hyprland.decoration")
require("hyprland.group")
require("hyprland.execs")
require("hyprland.rules")
require("hyprland.gestures")
require("hyprland.keybinds")

-- User-created keybindings managed by Nexus > Keyboard shortcuts.
require("custom-shortcuts")

-- User configs
maybe_create(home .. "/.config/caelestia/hypr-user.lua")
require("hypr-user")

-- Simple plugin controls managed by Nexus. Loaded after advanced user settings
-- so changes made in the Plugins page take effect predictably.
require("plugin-settings")

-- HyprMod managed settings
require("hyprland-gui")

-- Keyboard layouts managed by Nexus, applied to the active Hyprland session.
maybe_create(home .. "/.config/caelestia/keyboard-overrides.lua")
require("keyboard-overrides")
keybind_editor.finish()
