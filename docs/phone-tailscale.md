# Phone Integration and Tailscale Mesh Network

**English** | [Türkçe](phone-tailscale.tr.md)

Atom Shell establishes a seamless, secure bidirectional bridge between your Android phone and desktop environment, operating smoothly whether you are on your local home Wi-Fi or connected remotely.

---

## 📱 Hybrid Connection Architecture

Phone connectivity leverages both the **KDE Connect** protocol and **Wired / Wireless ADB** channels in tandem:

- **Live Battery & Connection Status:** The top taskbar (`bar/components/Phone.qml`) and Dashboard phone tab (`dashboard/Phone.qml`) display real-time battery percentage, charging state, and current connection route (USB, Local Wi-Fi, Tailscale, or Bluetooth).
- **Drag-and-Drop File Transfer:** Simply drag any file or image into the Dashboard Phone tab to send it wirelessly to your phone storage.
- **Media & Volume Control:** Control playback on your phone, skip tracks, and adjust phone audio volume directly from the desktop shell.

---

## 🛠️ Built-in Automation Commands (`config/bin/`)

| Command | Description |
|---|---|
| `phone-control` | Unified CLI tool for querying status, battery, media controls, and automation triggers. |
| `phone-mirror` | Launches low-latency screen mirroring and control via `scrcpy`. |
| `phone-answer` | Pick up and answer incoming phone calls directly from your desktop. |
| `phone-ring` | Ring the phone at full volume to quickly locate it, even if set to silent. |
| `phone-wifi` | Automatically establishes wireless ADB pairing over the local Wi-Fi network. |
| `phone-clipboard-image` | Instantly synchronizes Wayland image clippings directly to the Android clipboard. |

---

## 🌐 Location-Independent Discovery via Tailscale

To maintain seamless synchronization when away from your local home network, Atom Shell integrates Tailscale mesh networking:

1. **Automatic Device Discovery (`config/bin/kdeconnect-tailscale-start`):** Scans `tailscale status --json` at startup, resolves your Android device's Tailscale IP, and registers it as a `customDevices` entry in `~/.config/kdeconnect/config`.
2. **Systemd Unit (`kdeconnect-tailscale.service`):** Ensures network connectivity is established before triggering discovery and maintaining active links.
3. **Hyprland Auto-Launch:** Configured in `config/hypr/hyprland/execs.lua`:
   ```lua
   hl.exec_cmd("systemctl --user start kdeconnect-tailscale.service")
   ```

---

## 🔒 Secure Automation & Clipboard Sync

- **Image Clipboard Service (`phone-clipboard-image.service`):** Monitors Wayland clipboard events via `wl-paste` and pushes images to the Android phone companion app.
- **Isolated Automation SSH Server (`phone-automation-sshd.service`):** Runs an isolated SSH daemon on port 8022 using public-key authentication only. Allows Tasker, Termux, or custom mobile automation flows to securely execute desktop scripts.
