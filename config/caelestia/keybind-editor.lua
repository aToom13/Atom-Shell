-- Keep dispatchers, Lua callbacks and flags intact when changing a shortcut.
local M = {}
local bind, unbind = hl.bind, hl.unbind
local path = os.getenv("HOME") .. "/.config/caelestia/keybind-overrides.lua"
local loader = loadfile(path)
local overrides = loader and loader() or {}

local function canonical(keys)
    local parts, mods = {}, {}
    for part in keys:gmatch("[^+]+") do
        table.insert(parts, part:match("^%s*(.-)%s*$"):lower())
    end
    local key = table.remove(parts)
    for _, part in ipairs(parts) do table.insert(mods, part) end
    table.sort(mods)
    table.insert(mods, key)
    return table.concat(mods, "+")
end

function M.start()
    _G.nexusKeybinds = {}
    hl.bind = function(keys, action, opts)
        local id = canonical(keys)
        local target = overrides[id] or keys
        local handle = bind(target, action, opts)
        _G.nexusKeybinds[id] = { original = keys, key = target }
        return handle
    end
    hl.unbind = function(keys)
        local id = canonical(keys)
        _G.nexusKeybinds[id] = nil
        return unbind(overrides[id] or keys)
    end
end

function M.finish()
    hl.bind, hl.unbind = bind, unbind
end

return M
