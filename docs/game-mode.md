# Game Mode, Frame Generation, and Performance Optimization

**English** | [Türkçe](game-mode.tr.md)

Atom Shell features an integrated **Game Mode** designed to deliver maximum frame rates (FPS), minimal input latency, and fluid frame pacing for Linux gaming.

---

## 🎮 Two-Tier Control Architecture

### 1. Quick Game Mode & Frame Generation Panel (`modules/utilities/cards/GameModePanel.qml`)
Accessible directly inside the Utilities Drawer (`Super + U`):
- **Frame Generation:** Instant toggle between Off, Automatic, 2x, and 3x modes.
- **Window & Game Selector:** Auto-detects running Vulkan/OpenGL/Wine clients and binds rendering optimizations to the chosen target.
- **3D Test Cube:** Launch an instant lightweight 3D testing scene (`vkcube` backend) to verify frame latency, VRR (Variable Refresh Rate), and tearing policies without needing a full game installed.
- **In-Game HUD (`modules/GameHud.qml`):** Displays real delivered FPS, CPU percentage, RAM consumption, and CPU temperature directly in an unobtrusive overlay. Position (top-right, top-left, bottom-right, etc.), margin, and font size are configurable.

### 2. Nexus System Configuration (`modules/nexus/pages/services/GameModePage.qml`)
Full system configuration accessible via Nexus Control Center:
- **Compositor Passthrough:** Automatically disables window animations, corner rounding, shadows, and blur layers. Allows fullscreen games to utilize Direct Scanout for zero-latency frame presentation.
- **Hardware Profile:** Automatically switches CPU governor and system power profiles to `performance`.
- **Do Not Disturb (DND):** Silences desktop toasts and notification sounds while playing.
- **Game Profiles (`config/caelestia/game-profiles.json`):** Automatic per-title launch parameters and custom render preferences for Steam, Lutris, and standalone native games.

---

## 🚀 Frame Generation Strategy

Frame Generation multiplies perceived motion smoothness when game engine FPS falls below the display refresh rate:
- If a game is already achieving native monitor refresh rate (e.g., 144 FPS on a 144 Hz screen), Frame Generation automatically remains in standby to avoid unnecessary compute overhead and input latency.
- When frame drops occur, intelligent motion vectors interpolate intermediate frames and maintain steady visual cadence.

---

## 🔧 Configuration Files

- **Game Mode Defaults:** `~/.config/caelestia/game-mode.json`
- **Saved Game Profiles:** `~/.config/caelestia/game-profiles.json`
- **Helper Scripts:** `utils/game_mode.py`, `utils/game_profiles.py`, and `services/GameProfiles.qml`
- **Steam Compatibility Launcher:** `config/bin/steam-sw`
