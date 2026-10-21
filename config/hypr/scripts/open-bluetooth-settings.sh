#!/usr/bin/env bash
set -euo pipefail

if kcmshell6 --list 2>/dev/null | awk '{print $1}' | grep -Fxq kcm_bluetooth; then
    exec kcmshell6 kcm_bluetooth
fi

if command -v blueman-manager >/dev/null 2>&1; then
    exec blueman-manager
fi

# The base install has System Settings but no Bluetooth settings module.
# Install the native KDE module in a visible terminal so authentication is
# explicit and any package-manager error remains visible to the user.
exec kitty --title 'Install Bluetooth settings' -e bash -lc '
    echo "The KDE Bluetooth settings module is not installed."
    echo
    sudo pacman -S --needed bluedevil
    code=$?
    echo
    if [ "$code" -eq 0 ]; then
        echo "Bluetooth settings installed. Opening it now..."
        sleep 1
        kcmshell6 kcm_bluetooth
    else
        echo "Installation exited with code $code."
        echo "Press Enter to close."
        read -r
    fi
'
