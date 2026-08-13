# Distribution notes

**English** | [Türkçe](DISTROS.tr.md)

## Arch Linux and CachyOS

This is the primary native target. The installer obtains Qt, Quickshell, Caelestia CLI, build tools, and desktop integrations through pacman and, when necessary, `paru` or `yay`. Native C++ plugins are linked against the installed Qt version, so run `atomshell update` or `./install.sh --no-packages` after a major Qt upgrade.

## Debian 13/14

Host integration services are installed with apt, while Nix provides a current Qt/Quickshell compatibility runtime. Debian's Hyprland package may be used when it is version 0.55 or newer; otherwise use the Nix Hyprland added to the user profile.

## Ubuntu and Linux Mint

Depending on the release, Ubuntu and Mint may ship Qt and Hyprland versions older than Atom Shell requires. The installer therefore defaults to the Nix runtime and adds Nix Hyprland to the profile. If the display manager still launches `/usr/bin/Hyprland`, create a Wayland session entry that launches `~/.nix-profile/bin/Hyprland`.

This target is marked experimental because portal, screen-sharing, and polkit agent package names vary across distribution releases. `atomshell doctor` reports missing functionality.

## Minimum versions

- Hyprland 0.55 for Lua configuration support
- Qt 6.9 for the Atom Shell v2.3 plugin CMake requirements
- Quickshell 0.3 or a current Git build
- CMake 3.19, a modern Ninja, and a C++20 compiler

## Package groups

Core: NetworkManager, PipeWire/WirePlumber, notification clients, jq, rsync, ripgrep, and Git.

Full profile: Bluetooth/Blueman, KDE Connect/SSHFS, udiskie, inotify-tools, screenshot tools, brightness/DDC controls, clipboard history, a polkit agent, keyring, Geoclue/Gammastep, and diagnostic utilities.

The installer skips optional apt packages unavailable on the current distribution; `atomshell doctor` reports the corresponding feature-level warnings.
