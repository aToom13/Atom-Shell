#!/usr/bin/env bash
set -euo pipefail

media_dir="/run/media/${USER}"

command -v inotifywait >/dev/null 2>&1 || {
    printf 'atomshell-usb-notify: inotifywait is not installed; notifications are disabled.\n' >&2
    exit 0
}

mkdir -p "$media_dir"

inotifywait --monitor --quiet --event create --event moved_to --event delete --event moved_from \
    --format '%e|%f' "$media_dir" | while IFS='|' read -r event label; do
    [[ -n $label ]] || continue
    case "$event" in
        CREATE*|MOVED_TO*)
            notify-send --urgency=low --app-name='Atom Shell' \
                --icon=media-removable-symbolic 'USB connected' "$label"
            ;;
        DELETE*|MOVED_FROM*)
            notify-send --urgency=low --app-name='Atom Shell' \
                --icon=media-removable-symbolic 'USB disconnected' "$label"
            ;;
    esac
done
