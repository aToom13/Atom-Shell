# Atom Shell

**English** | [Türkçe](README.tr.md)

Atom Shell is a personal Hyprland desktop layer based on Caelestia Shell v2.3, with its own safe installation, update, backup, and rollback workflow. It keeps custom Nexus pages, advanced network diagnostics, device management, and a portable Hyprland configuration in one repository.

> Atom Shell is an independent fork and is not an official Caelestia release. Internal QML namespaces and the `~/.config/caelestia` schema remain unchanged for upstream compatibility.

## Highlights

- Nexus pages for displays, updates, plugins, keyboard shortcuts, power/lock, and detailed service settings
- Wi-Fi, Ethernet, saved networks, NetworkManager VPN profiles, and v2.3 VPN provider management
- Live connection data, network/DNS/HTTPS diagnostics, and LAN/USB/KDE Connect discovery
- Configurable taskbar entries, status icons, quick toggles, and utility panels
- One-command install, update, diagnostics, uninstall, and rollback
- Timestamped backups before modifying existing user files
- Native runtime on Arch/CachyOS and a modern Nix-based Qt/Quickshell runtime on Debian/Ubuntu/Mint

## Support status

| Distribution | Runtime | Status |
|---|---|---|
| Arch Linux | Native Qt 6.9+, Quickshell | Fully supported |
| CachyOS | Native Qt 6.9+, Quickshell | Fully supported |
| Debian 13/14 | Nix runtime + apt integration packages | Supported |
| Ubuntu / Linux Mint | Nix runtime + apt integration packages | Experimental; Hyprland 0.55+ required |

Hyprland 0.55 introduced the Lua configuration API used by this project, so older versions are unsupported. If Ubuntu or Mint ships an older Hyprland, the installer adds a current Nix Hyprland to the user profile; the session manager must also be configured to launch that binary. See [distribution notes](docs/DISTROS.md).

## Installation

```bash
git clone https://github.com/aToom13/Atom-Shell.git
cd Atom-Shell
./install.sh --dry-run
./install.sh
```

Do not run the installer as root. It invokes `sudo` visibly only when system packages must be installed.

The default `merge` mode preserves existing values in `~/.config/caelestia` and `~/.config/hypr`, adding only missing templates. Known v2.2 `bar.status` settings and legacy Hyprland launch commands are migrated automatically after a full directory backup. To apply the complete desktop configuration from this repository, use:

```bash
./install.sh --config-mode replace
```

`replace` backs up both configuration directories first. Other useful options:

```text
--dry-run                 Show the plan without changing anything
--no-packages             Do not invoke a package manager
--no-build                Do not rebuild the Qt/QML runtime
--profile minimal|full    Install core or complete integrations
--runtime auto|native|nix Select the runtime method
--install-nix             Install Nix from the official installer if missing
--config-mode merge|replace|skip
```

For an automated Debian/Ubuntu/Mint installation:

```bash
./install.sh --install-nix
```

## Usage

```bash
atomshell start
atomshell stop
atomshell restart
atomshell status
atomshell settings
atomshell doctor
```

If `~/.local/bin` is not in `PATH`, add it to your shell profile:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Update safety

A normal system upgrade does not remove Atom Shell:

- Shell sources live in the user-owned `~/.config/quickshell/caelestia` directory.
- Native compiled plugins live under `~/.local/share/atomshell/runtime`.
- Package-owned files in `/usr/share` and `/etc/xdg` are never modified.
- Quickshell selects the user configuration before `/etc/xdg/quickshell/caelestia`.

The local plugin must be rebuilt after a Qt or Quickshell ABI change. The safe updater handles this:

```bash
atomshell update --check
atomshell update
```

The updater refuses a dirty Git tree or diverged history, accepts only a fast-forward update, runs smoke tests, and reinstalls with a backup.

Do not launch the shell directly with `qs -c caelestia` or `caelestia shell`. If a v2.2 system package remains installed, it can load the v2.3 configuration through the old plugin and report `Unknown option bar.statusIcons`. `atomshell start/restart` always selects the project-owned runtime.

## Backup, rollback, and removal

Backups are stored in:

```text
~/.local/state/atomshell/backups/YYYYMMDD-HHMMSS[-N]/
```

List or restore a backup with:

```bash
./rollback.sh
./rollback.sh ~/.local/state/atomshell/backups/20260813-150000
```

Uninstalling preserves user configuration by default:

```bash
atomshell uninstall
atomshell uninstall --purge-config
```

System packages installed by the setup are deliberately not removed automatically because other desktop components may use them.

## Repository layout

```text
assets/, components/, modules/, services/, utils/  Shell sources
plugin/, extras/                                    Compiled compatibility modules
config/caelestia/                                   Portable shell configuration templates
config/hypr/                                        Hyprland Lua configuration and helpers
scripts/                                            Installation infrastructure
docs/                                               Architecture and distribution docs
tests/                                              Static and dry-run validation
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and upstream merges, [SECURITY.md](SECURITY.md) for the security model, and [ARCHITECTURE.md](docs/ARCHITECTURE.md) for the runtime design.

## Origin and license

Atom Shell is derived from the GPL-3.0-only [Caelestia Shell](https://github.com/caelestia-dots/shell) project and is distributed under the same license. Copyright notices for the original project and its contributors are preserved. See [LICENSE](LICENSE).
