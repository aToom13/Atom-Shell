#!/usr/bin/env bash
set -euo pipefail

if kcmshell6 --list 2>/dev/null | awk '{print $1}' | grep -Fxq kcm_bluetooth; then
    exec kcmshell6 kcm_bluetooth
fi

if command -v blueman-manager >/dev/null 2>&1; then
    exec blueman-manager
fi

notify-send --urgency=normal --app-name='Atom Shell' \
    'Bluetooth settings unavailable' \
    'Install Blueman (recommended) or the KDE Bluetooth settings module.'
