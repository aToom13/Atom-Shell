# Nexus Control Center

**English** | [Türkçe](nexus.tr.md)

Nexus (`modules/nexus/`) is the built-in graphical settings and control center that manages all visual, hardware, and behavioral aspects of Atom Shell.

## 🚀 Access and Shortcuts

- **Keyboard Shortcut:** `Super + I`
- **Command Line (CLI):** `atomshell nexus` or `quickshell ipc call nexus open`
- **Top Bar:** Quick access from clock or status icons

---

## 📑 Nexus Pages Overview

Nexus contains 15 specialized configuration pages:

| No | Page | Icon | Category | Description & Capabilities |
|:---:|---|---|---|---|
| **0** | **Wallpaper & style** | `palette` | Appearance | **Wallpaper & Color Scheme:** Active wallpaper selector, Material You (M3) dynamic color generation from wallpapers, blur, and transparency settings (`services/Colours.qml`). |
| **1** | **Display** | `monitor` | Connectivity | **Monitors & Resolutions:** Displays, refresh rates (Hz), fractional scaling, and drag-and-drop monitor layout arrangement with 15-second automatic rollback safety (`display_settings.py`, `monitor-overrides.tsv`). |
| **2** | **Network** | `wifi` | Connectivity | **Network Management:** Wi-Fi scanning, password entry, static IP/DNS, Ethernet status, WireGuard/Tailscale VPN profiles, security auditing, and Wi-Fi QR code sharing (`network-security.sh`, `wifi-qr.sh`). |
| **3** | **Connected devices** | `devices_other` | Connectivity | **Connected Devices:** Bluetooth pairing, trusted devices, battery monitoring, KDE Connect status, and connected USB device management (`modules/nexus/pages/BluetoothPage.qml`). |
| **4** | **Audio** | `volume_up` | Connectivity | **Audio Mixer:** Default audio input/output devices, per-application volume sliders, and PipeWire / WirePlumber routing (`services/Audio.qml`). |
| **5** | **Power & lock** | `lock_clock` | System | **Power & Lock Screen:** Screen lock timeout, idle behavior, suspend/hibernate profiles, and Graceful Hibernation threshold settings (`modules/nexus/pages/PowerAndLockPage.qml`). |
| **6** | **Updates** | `system_update` | System | **System Updates:** Unified package updates across Pacman, AUR (yay/paru), and Flatpak with package details, live terminal update runner, and schedule settings (`services/UpdateRunner.qml`). |
| **7** | **Plugins** | `extension` | System | **Hyprland Plugins:** `hyprpm` integration for installing, compiling, enabling, and configuring Hyprland plugins at runtime (`config/hypr/scripts/manage-plugin-settings.sh`). |
| **8** | **Keyboard shortcuts** | `keyboard` | System | **Shortcut Editor:** Search, filter, detect conflicts, and visually assign keybindings for windows, workspaces, and shell features (`utils/builtin_shortcuts.py`, `config/hypr/shortcuts.txt`). |
| **9** | **Panels** | `dock_to_bottom` | Shell | **Panel Customization:** Taskbar and sidebar modules, launcher folders (`launcher-folders.json`), popout behavior, and compact mode options (`modules/nexus/pages/PanelsPage.qml`). |
| **10** | **Apps** | `apps` | Shell | **Application Management:** Default browser, terminal, file manager MIME associations (`utils/default_apps.py`), autostart session entries (`utils/autostart.py`), and hidden apps. |
| **11** | **Services** | `build` | Shell | **Background Services:** Polling intervals, weather API and location coordinates, lyrics provider priority (LRCLIB/NetEase), and phone automation policies (`config/caelestia/shell.json`). |
| **12** | **Language & region** | `globe` | Shell | **Language & Region:** UI language (English / Turkish), clock format (12h/24h), weather units (°C/°F), keyboard layouts, and number formatting (`utils/region.py`, `services/I18n.qml`). |
| **13** | **Game Mode** | `gamepad` | Shell | **Game Mode Settings:** System power profiles, CPU governor, compositor animations/blur suppression, Do Not Disturb automation, and game profile associations (`services/GameMode.qml`, `utils/game_mode.py`). |
| **14** | **About** | `info` | Information | **System Information:** Linux distribution, kernel release, Hyprland and Quickshell versions, hardware specifications, and system diagnostics (`modules/nexus/pages/AboutPage.qml`). |

---

## 🛠️ Architecture and Data Flow

1. **Live State Persistence:** Settings changed in Nexus are automatically saved to user JSON configs in `~/.config/caelestia/` and dispatched immediately to active shell singletons without restarting.
2. **Safety Rollback:** Critical hardware modifications (such as display layout and refresh rate) invoke a 15-second confirmation dialog, automatically reverting to the previous known-good state if not confirmed.
3. **Lazy Page Loading:** Pages are dynamically instantiated via `modules/nexus/PageRegistry.qml` to ensure optimal memory consumption and instantaneous launch times.
