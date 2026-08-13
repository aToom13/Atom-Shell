# Contributing and upstream updates

**English** | [Türkçe](CONTRIBUTING.tr.md)

Run `./tests/smoke.sh` before submitting a change. Native development also requires a CMake build and an `atomshell restart` test inside a running Hyprland session.

Follow the upstream Caelestia Shell code style. Do not rename internal `Caelestia.*` namespaces solely for branding; doing so makes upstream merges unnecessarily difficult.

## Merging an upstream v2.x release

```bash
git fetch upstream --tags
git switch main
git merge --no-ff v2.3.0
./tests/smoke.sh
./install.sh --dry-run --no-packages
```

Resolve conflicts by preserving Atom Shell's additional Nexus pages. When the upstream configuration API changes, migrate custom pages to the new API. In particular, QML accesses `ConfigList` fields through `.values`, `.count`, `.at()`, `.insert()`, `.move()`, and `.remove()`.

Rebuild the native runtime after a merge. Visually test networking, audio, lock screen, taskbar, launcher, notifications, and device pages.
