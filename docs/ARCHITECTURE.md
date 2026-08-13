# Architecture

**English** | [Türkçe](ARCHITECTURE.tr.md)

Atom Shell separates three layers:

1. `~/.config/quickshell/caelestia`: live QML shell sources. The directory name remains fixed for compatibility with Caelestia CLI IPC calls using `qs -c caelestia`.
2. `~/.local/share/atomshell/runtime`: native C++/QML plugins and helper libraries. No files overlap with system packages.
3. `~/.config/caelestia` and `~/.config/hypr`: user-owned configuration. Updates add only missing files by default.

`~/.local/bin/atomshell` sets the required `QML_IMPORT_PATH` and `CAELESTIA_LIB_DIR`. A native installation executes the system `qs`; a Nix installation executes `atomshell-runtime`. Both open the shell under the `caelestia` Quickshell configuration identity for IPC compatibility.

The launcher terminates an old `quickshell -d` supervisor by PID instead of killing only its child and allowing it to respawn with a v2.2 runtime. Hyprland startup and restart key bindings therefore invoke `atomshell` directly.

This separation allows the system `caelestia-shell` package to remain installed. Even when that package updates files under `/etc/xdg`, Quickshell selects the user copy first. Atom Shell does not patch package-owned files.

## Installation flow

- Detect the distribution and select a runtime.
- Install optional system integration packages.
- In native mode, build plugin/extras/m3shapes into a user prefix with CMake; in Nix mode, add the flake package to the profile.
- Back up the old live shell and refresh managed source directories with controlled `rsync --delete` operations.
- Apply the selected `merge`, `replace`, or `skip` policy to user configuration.
- During a merge, migrate v2.2 `bar.status` values losslessly into `bar.statusIcons` and replace legacy Hyprland shell commands with `atomshell`, after backing up the complete directories.
- Record the source repository and runtime type in the install manifest.

## Configuration ownership

Atom Shell manages the live shell source directory. Manual edits are possible, but moving those changes into the Git repository before an update is recommended. The installer backs up the complete live shell before every refresh, so local changes remain recoverable.

The user owns `~/.config/caelestia` and `~/.config/hypr`. `merge` does not overwrite existing values. `replace` is used only when explicitly requested and only after a backup.
