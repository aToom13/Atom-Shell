# Security

**English** | [Türkçe](SECURITY.tr.md)

## Installer security model

- `install.sh` refuses to run as root.
- System changes are limited to distribution package installation and the optional official Nix installer; `sudo` is invoked visibly when required.
- `--dry-run` displays commands without modifying files or packages.
- User files are copied to `~/.local/state/atomshell/backups` before modification.
- The uninstaller deliberately leaves system packages installed.
- The former root/udev-based USB notification setup is not used; notifications run entirely in the user session.

When Nix installation is requested, the script downloads only `https://nixos.org/nix/install` with TLS enforcement and proceeds only after `--install-nix` or interactive user approval.

## Reporting a vulnerability

If you discover command injection, privilege escalation, or sensitive-data exposure, submit a private GitHub security advisory to the repository owner before opening a public issue. Include the affected commit, reproduction steps, and expected impact.
