#!/usr/bin/env bash
set -euo pipefail

# Sourced by install.sh after common.sh.

install_arch_packages() {
    local -a build runtime optional aur
    build=(
        base-devel cmake ninja git rsync jq curl pkgconf
        qt6-base qt6-declarative qt6-shadertools qt6-wayland qt6-svg qt6-imageformats
        pipewire libpipewire aubio libcava fftw libqalculate lm_sensors
    )
    runtime=(
        hyprland networkmanager bluez bluez-utils blueman pipewire wireplumber
        polkit-gnome gnome-keyring ddcutil brightnessctl swappy grim slurp
        wl-clipboard cliphist fuzzel gammastep geoclue kitty thunar pavucontrol
        playerctl udiskie inotify-tools trash-cli kdeconnect sshfs libnotify fish
    )
    optional=(avahi nmap openbsd-netcat usbutils hwdata zenity)
    aur=(quickshell-git caelestia-cli ttf-material-symbols-variable-git ttf-cascadia-code-nerd)

    log "Arch/CachyOS paketleri kuruluyor"
    run_root pacman -S --needed "${build[@]}" "${runtime[@]}"
    if [[ ${PROFILE:-full} == full ]]; then
        run_root pacman -S --needed "${optional[@]}"
    fi

    local helper=
    for candidate in paru yay; do
        if command -v "$candidate" >/dev/null 2>&1; then
            helper=$candidate
            break
        fi
    done
    if [[ -n $helper ]]; then
        run "$helper" -S --needed "${aur[@]}"
        return
    fi

    # CachyOS and some Arch derivatives carry these packages in a binary repo.
    local -a repo_packages=()
    local package
    for package in quickshell caelestia-cli ttf-cascadia-code-nerd; do
        pacman -Si "$package" >/dev/null 2>&1 && repo_packages+=("$package")
    done
    ((${#repo_packages[@]})) && run_root pacman -S --needed "${repo_packages[@]}"
    command -v qs >/dev/null 2>&1 || [[ $DRY_RUN == true ]] || \
        die "Quickshell bulunamadı. paru/yay ile quickshell-git paketini kurun."
}
apt_available() {
    apt-cache show "$1" >/dev/null 2>&1
}

install_debian_packages() {
    local -a wanted available
    wanted=(
        git curl rsync jq ca-certificates xz-utils
        network-manager bluez blueman pipewire wireplumber policykit-1-gnome
        gnome-keyring libnotify-bin brightnessctl ddcutil lm-sensors swappy
        grim slurp wl-clipboard fuzzel gammastep geoclue-2.0 kitty thunar
        pavucontrol playerctl udiskie inotify-tools trash-cli kdeconnect sshfs
        avahi-daemon nmap netcat-openbsd usbutils hwdata zenity fish
    )
    if [[ ${PROFILE:-full} == minimal ]]; then
        wanted=(git curl rsync jq ca-certificates xz-utils network-manager pipewire wireplumber libnotify-bin)
    fi
    local package
    for package in "${wanted[@]}"; do
        apt_available "$package" && available+=("$package")
    done
    log "Debian/Ubuntu/Mint entegrasyon paketleri kuruluyor"
    run_root apt-get update
    ((${#available[@]})) && run_root apt-get install -y "${available[@]}"
}

install_packages() {
    case $DISTRO_FAMILY in
        arch) install_arch_packages ;;
        debian) install_debian_packages ;;
        *) die "Desteklenmeyen dağıtım: $DISTRO_ID. --no-packages ile elle kuruluma geçebilirsiniz." ;;
    esac
}
