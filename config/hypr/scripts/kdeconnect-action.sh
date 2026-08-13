#!/usr/bin/env bash
set -euo pipefail

action=${1:-}
device=${2:-}
[[ "$device" =~ ^[A-Za-z0-9_-]+$ ]] || { printf 'Invalid KDE Connect device ID.\n' >&2; exit 2; }

device_path="/modules/kdeconnect/devices/$device"
sftp_path="$device_path/sftp"

reachable() {
    kdeconnect-cli -a --id-only 2>/dev/null | grep -Fxq "$device"
}

case "$action" in
    clipboard)
        reachable || { printf 'Device is not reachable.\n' >&2; exit 1; }
        text=$(wl-paste --no-newline 2>/dev/null || true)
        [[ -n "$text" ]] || { printf 'The local clipboard does not contain text.\n' >&2; exit 1; }
        # Explicitly select the Wayland backend. Without it, a short-lived Qt
        # CLI process can see an empty clipboard in non-Plasma shells.
        QT_QPA_PLATFORM=wayland kdeconnect-cli --send-clipboard -d "$device"
        printf 'Clipboard text sent (%d characters).\n' "${#text}"
        ;;
    share-text)
        reachable || { printf 'Device is not reachable.\n' >&2; exit 1; }
        text=$(wl-paste --no-newline 2>/dev/null || true)
        [[ -n "$text" ]] || { printf 'The local clipboard does not contain text.\n' >&2; exit 1; }
        kdeconnect-cli --share-text "$text" -d "$device"
        printf 'Clipboard text shared with the device.\n'
        ;;
    browse)
        reachable || { printf 'Device is not reachable.\n' >&2; exit 1; }
        command -v sshfs >/dev/null || {
            printf 'SSHFS is required for KDE Connect file browsing but is not installed.\n' >&2
            exit 10
        }
        # A previous SSHFS process may still be marked as mounted after the
        # phone locked or changed networks. Start from a clean session.
        busctl --user call org.kde.kdeconnect "$sftp_path" org.kde.kdeconnect.device.sftp unmount >/dev/null 2>&1 || true
        sleep 0.3
        busctl --user call org.kde.kdeconnect "$sftp_path" org.kde.kdeconnect.device.sftp mountAndWait >/dev/null
        mounted=$(busctl --user call org.kde.kdeconnect "$sftp_path" org.kde.kdeconnect.device.sftp isMounted | awk '{print $2}')
        if [[ "$mounted" != true ]]; then
            error=$(busctl --user call org.kde.kdeconnect "$sftp_path" org.kde.kdeconnect.device.sftp getMountError | sed 's/^s //; s/^"//; s/"$//')
            printf '%s\n' "${error:-The phone filesystem could not be mounted.}" >&2
            printf 'Unlock the phone, then in KDE Connect open Plugin settings > Filesystem expose, grant storage access, and try again.\n' >&2
            exit 1
        fi
        path=$(kdeconnect-cli --get-mount-point -d "$device" 2>/dev/null)
        sleep 0.4
        if [[ -z "$path" || ! -d "$path" ]] || ! mountpoint -q "$path"; then
            error=$(busctl --user call org.kde.kdeconnect "$sftp_path" org.kde.kdeconnect.device.sftp getMountError 2>/dev/null | sed 's/^s //; s/^"//; s/"$//' || true)
            printf '%s\n' "${error:-KDE Connect did not create a usable phone-storage mount.}" >&2
            printf 'Unlock the phone, then in KDE Connect open Plugin settings > Filesystem expose, grant storage access, and try again.\n' >&2
            exit 1
        fi

        # KDE Connect exposes one or more Android directories below the SSHFS
        # root. Opening the raw mount root looks empty in Dolphin on Android.
        directory_data=$(busctl --user call org.kde.kdeconnect "$sftp_path" org.kde.kdeconnect.device.sftp getDirectories 2>/dev/null || true)
        remote_path=$(sed -n 's/^[^"]*"\([^"]*\)".*/\1/p' <<<"$directory_data" | head -n 1)
        if [[ -n "$remote_path" && "$remote_path" == "$path"* ]]; then
            browse_path="$remote_path"
        else
            browse_path="$path${remote_path:-}"
        fi

        if ! timeout 8 ls -A "$browse_path" >/dev/null 2>&1; then
            error=$(busctl --user call org.kde.kdeconnect "$sftp_path" org.kde.kdeconnect.device.sftp getMountError 2>/dev/null | sed 's/^s //; s/^"//; s/"$//' || true)
            busctl --user call org.kde.kdeconnect "$sftp_path" org.kde.kdeconnect.device.sftp unmount >/dev/null 2>&1 || true
            printf '%s\n' "${error:-Phone storage is not accessible.}" >&2
            printf 'Unlock the phone, then in KDE Connect open Plugin settings > Filesystem expose, grant storage access, and try again.\n' >&2
            exit 1
        fi

        xdg-open "$browse_path" >/dev/null 2>&1 &
        printf 'Opened phone storage: %s\n' "$browse_path"
        ;;
    install-sshfs)
        notify-send --urgency=normal --app-name='Atom Shell' \
            'KDE Connect needs SSHFS' \
            'Install the sshfs package with your distribution package manager, then try again.'
        ;;
    *)
        printf 'usage: %s {clipboard|share-text|browse|install-sshfs} DEVICE_ID\n' "$0" >&2
        exit 2
        ;;
esac
