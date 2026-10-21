# Keyboard Shortcuts and Window Management Guide

**English** | [Türkçe](shortcuts.tr.md)

Atom Shell provides a coherent, ergonomic, and conflict-free keyboard shortcuts configuration built on top of the Hyprland v0.55+ Lua binding system (`config/hypr/hyprland/keybinds.lua`).

---

## ⚡ Instant Shortcut Search & HUD

- **Shortcut:** `F12` or `Super + Shift + H`
- **Function:** Opens a translucent, instantly filterable shortcut search overlay (`utils/builtin_shortcuts.py`). Type any action or key name to see active bindings on the fly.

---

## ⌨️ Essential Keyboard Shortcuts

### Desktop and Shell Navigation

| Shortcut | Action |
|---|---|
| `SUPER + SUPER_L` (Super tap) | Toggle Application Launcher |
| `SUPER + Tab` | Window Overview / Exposé |
| `SUPER + I` | Open Nexus Control Center |
| `F9` | Toggle Notification Center & Sidebar |
| `SUPER + U` | Open Quick Settings & Utilities Drawer |
| `SUPER + D` | Toggle Dashboard |
| `ALT + F4` / `SUPER + Backspace` | Open Session & Power Menu (Shutdown, Restart, Lock) |
| `SUPER + L` | Lock Screen |
| `SUPER + V` | Open Clipboard History (Cliphist) |

### Application Launchers

| Shortcut | Application |
|---|---|
| `SUPER + T` / `SUPER + Enter` | Terminal (`foot` / `kitty`) |
| `SUPER + E` | File Manager (`thunar`) |
| `SUPER + C` | Code Editor (IDE / VS Code) |
| `F7` | Display & Monitor Preferences |

### Window Management & Tiling

| Shortcut | Action |
|---|---|
| `SUPER + Q` | Close Active Window |
| `ALT + TAB` | Quick switch between windows in active workspace |
| `SUPER + F` | Toggle Fullscreen |
| `SUPER + ALT + F` | Toggle Maximized (Retains shell borders) |
| `SUPER + ALT + Space` | Toggle Floating / Tiled mode |
| `SUPER + B` | Toggle Window Tabbed Grouping |
| `SUPER + P` | Pin Window (Keeps window visible across all workspaces) |
| `SUPER + Left/Right/Up/Down` | Move focus in direction |
| `SUPER + SHIFT + Left/Right/Up/Down` | Move window in direction |
| `SUPER + CTRL + Left/Right/Up/Down` | Resize window in direction |

### Special Workspaces (Scratchpads)

| Shortcut | Workspace |
|---|---|
| `SUPER + S` | Scratchpad / General Special Workspace |
| `SUPER + M` | Music Player Special Workspace |
| `SUPER + G` | Games & Performance Special Workspace |
| `SUPER + O` | Communication & Chat Special Workspace |

### Utilities and Media Controls

| Shortcut | Action |
|---|---|
| `Print` / `SUPER + SHIFT + S` | Area Selection for Screenshot or Screen Recording |
| `F10` | Start / Stop Speech-to-Text Voice Dictation |
| `F11` | Extract & Copy Text from Screen Region (OCR) |
| `CTRL + SUPER + Space` | Media Play / Pause |
| `CTRL + SUPER + Page Down` | Next Track |
| `CTRL + SUPER + Page Up` | Previous Track |
| `XF86AudioRaiseVolume` | Volume Up |
| `XF86AudioLowerVolume` | Volume Down |
| `XF86AudioMute` | Mute Audio |
| `XF86MonBrightnessUp` | Brightness Up |
| `XF86MonBrightnessDown` | Brightness Down |

---

## 🛠️ Custom Keybinding Overrides

You can add custom keybindings without modifying tracked repository files either through the Nexus > Keyboard shortcuts page, or by editing `~/.config/caelestia/keybind-overrides.lua`. All changes take effect immediately without restarting Hyprland.
