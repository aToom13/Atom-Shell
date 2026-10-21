#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=scripts/install-packages.sh
source "$ROOT/scripts/install-packages.sh"

DRY_RUN=false
NON_INTERACTIVE=false
INSTALL_PACKAGES=true
BUILD_RUNTIME=true
CONFIG_MODE=merge
PROFILE=full
RUNTIME=auto
INSTALL_NIX=false

usage() {
    cat <<EOF
Kullanım / Usage: $0 [seçenekler / options]

  --dry-run                 Hiçbir şeyi değiştirmeden yapılacakları göster / Preview actions without modifying
  --no-packages             Sistem paketlerine dokunma / Skip system package installation
  --no-build                Derlenmiş runtime'ı değiştirme / Skip building/updating native runtime
  --non-interactive         Soruları güvenli varsayımlarla geç / Non-interactive unattended mode
  --config-mode MODE        merge (varsayılan/default), replace veya/or skip
  --profile PROFILE         full (varsayılan/default) veya/or minimal
  --runtime MODE            auto, native veya/or nix
  --install-nix             Eksikse resmi Nix kurucusunu çalıştır / Install official Nix if missing
  -h, --help                Bu yardımı göster / Show this help
EOF
}

INTERACTIVE_PROMPTS=true

while (($#)); do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        --no-packages) INSTALL_PACKAGES=false ;;
        --no-build) BUILD_RUNTIME=false ;;
        --non-interactive) NON_INTERACTIVE=true; INTERACTIVE_PROMPTS=false ;;
        --config-mode) shift; CONFIG_MODE=${1:-}; INTERACTIVE_PROMPTS=false ;;
        --profile) shift; PROFILE=${1:-}; INTERACTIVE_PROMPTS=false ;;
        --runtime) shift; RUNTIME=${1:-} ;;
        --install-nix) INSTALL_NIX=true ;;
        -h|--help) usage; exit 0 ;;
        *) die "Bilinmeyen seçenek: $1" ;;
    esac
    shift
done

ensure_user
detect_distro

if [[ $NON_INTERACTIVE == false && -t 0 && $INTERACTIVE_PROMPTS == true ]]; then
    printf '\n\033[1;36m=== Atom Shell Kurulum Sihirbazı / Setup Wizard ===\033[0m\n'
    printf 'Ön kontroller / Pre-flight checks:\n'
    printf '  • Dağıtım / Distro:    %s (%s)\n' "$DISTRO_ID" "$DISTRO_FAMILY"
    printf '  • Wayland oturumu:     %s\n' "${WAYLAND_DISPLAY:-Yok / Not active}"
    if command -v hyprctl >/dev/null 2>&1; then
        hypr_ver=$(hyprctl version 2>/dev/null | sed -nE 's/.*[Vv]ersion[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1)
        printf '  • Hyprland:            %s\n' "${hypr_ver:-Mevcut / Found}"
    else
        printf '  • Hyprland:            Kurulu değil / Not found\n'
    fi
    printf '  • Quickshell:          %s\n' "$(command -v qs >/dev/null 2>&1 && echo 'Mevcut / Found' || echo 'Kurulacak / Will install')"
    printf '\n'

    read -r -p "Kurulum profili / Installation profile [1: full (varsayılan), 2: minimal] (1): " ans_prof || ans_prof=""
    case "$ans_prof" in
        2|minimal) PROFILE=minimal ;;
        *) PROFILE=full ;;
    esac

    read -r -p "Yapılandırma modu / Config mode [1: merge (varsayılan), 2: replace, 3: skip] (1): " ans_cfg || ans_cfg=""
    case "$ans_cfg" in
        2|replace) CONFIG_MODE=replace ;;
        3|skip) CONFIG_MODE=skip ;;
        *) CONFIG_MODE=merge ;;
    esac

    if confirm "Eksik sistem paketleri kurulsun mu? / Install system packages?" yes; then
        INSTALL_PACKAGES=true
    else
        INSTALL_PACKAGES=false
    fi
    printf '\n'
fi

[[ $CONFIG_MODE =~ ^(merge|replace|skip)$ ]] || die "Geçersiz --config-mode: $CONFIG_MODE"
[[ $PROFILE =~ ^(minimal|full)$ ]] || die "Geçersiz --profile: $PROFILE"
[[ $RUNTIME =~ ^(auto|native|nix)$ ]] || die "Geçersiz --runtime: $RUNTIME"
export DRY_RUN NON_INTERACTIVE PROFILE

if [[ $RUNTIME == auto ]]; then
    [[ $DISTRO_FAMILY == arch ]] && RUNTIME=native || RUNTIME=nix
fi

VERSION=$(<"$ROOT/VERSION")
new_backup
log "Atom Shell $VERSION kurulumu ($DISTRO_ID, $RUNTIME runtime)"

if [[ $INSTALL_PACKAGES == true ]]; then
    install_packages
else
    log "Paket kurulumu atlandı"
fi

load_nix() {
    command -v nix >/dev/null 2>&1 && return 0
    if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        # shellcheck disable=SC1091
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
    command -v nix >/dev/null 2>&1
}

install_nix_runtime() {
    if ! load_nix; then
        if [[ $INSTALL_NIX != true ]]; then
            if confirm "Nix bulunamadı. Resmi çok-kullanıcılı Nix kurulsun mu?" no; then
                INSTALL_NIX=true
            else
                die "Debian/Ubuntu/Mint için modern Qt/Quickshell runtime'ı Nix gerektiriyor. --install-nix kullanın."
            fi
        fi
        if [[ $DRY_RUN == true ]]; then
            log "Resmi Nix kurucusu indirilecek ve --daemon ile çalıştırılacak"
        else
            local installer
            installer=$(mktemp)
            trap 'rm -f -- "$installer"' RETURN
            curl --fail --location --proto '=https' --tlsv1.2 https://nixos.org/nix/install -o "$installer"
            sh "$installer" --daemon --yes
            load_nix || die "Nix kuruldu ancak bu oturumda bulunamadı; yeni bir terminal açıp kurulumu yineleyin."
        fi
    fi
    backup_item "$HOME/.nix-profile" nix-profile
    if [[ $DRY_RUN == true ]]; then
        log "Nix profiline Atom runtime, Hyprland ve Caelestia CLI kurulacak"
        return
    fi
    nix --extra-experimental-features 'nix-command flakes' profile install \
        "path:$ROOT#with-cli" nixpkgs#hyprland
}

build_native_runtime() {
    local build_dir=$ROOT/.build/native
    command -v cmake >/dev/null 2>&1 || die "cmake bulunamadı"
    command -v ninja >/dev/null 2>&1 || die "ninja bulunamadı"
    backup_item "$ATOM_RUNTIME_DIR" atomshell/runtime
    if [[ $DRY_RUN == true ]]; then
        log "C++/QML eklentileri yerel kullanıcı runtime'ına derlenecek"
        return
    fi
    rm -rf -- "$build_dir"
    cmake -S "$ROOT" -B "$build_dir" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$ATOM_RUNTIME_DIR" \
        -DINSTALL_LIBDIR=lib/caelestia \
        -DINSTALL_QMLDIR=lib/qt6/qml \
        -DENABLE_MODULES='extras;plugin;m3shapes' \
        -DDISTRIBUTOR=atom-shell
    cmake --build "$build_dir"
    rm -rf -- "$ATOM_RUNTIME_DIR"
    cmake --install "$build_dir"
}

if [[ $BUILD_RUNTIME == true ]]; then
    case $RUNTIME in
        native) build_native_runtime ;;
        nix) install_nix_runtime ;;
    esac
else
    log "Runtime derlemesi/kurulumu atlandı"
fi

install_shell_source() {
    backup_item "$ATOM_SHELL_DIR" quickshell/caelestia
    run mkdir -p "$ATOM_SHELL_DIR"
    local dir
    for dir in assets components modules services utils i18n translations; do
        run mkdir -p "$ATOM_SHELL_DIR/$dir"
        run rsync -a --delete "$ROOT/$dir/" "$ATOM_SHELL_DIR/$dir/"
    done
    run install -m 0644 "$ROOT/shell.qml" "$ATOM_SHELL_DIR/shell.qml"
    run install -m 0644 "$ROOT/LICENSE" "$ATOM_SHELL_DIR/LICENSE"
}

install_config_tree() {
    local source=$1 target=$2 label=$3
    case $CONFIG_MODE in
        skip) return ;;
        merge)
            run mkdir -p "$target"
            run rsync -a --ignore-existing "$source/" "$target/"
            ;;
        replace)
            backup_item "$target" "$label"
            run mkdir -p "$target"
            run rsync -a --delete "$source/" "$target/"
            ;;
    esac
}

LEGACY_BAR_STATUS=false
if [[ $CONFIG_MODE == merge && -f $ATOM_CONFIG_DIR/shell.json ]] && \
        jq -e '.bar.status? | type == "object"' "$ATOM_CONFIG_DIR/shell.json" >/dev/null; then
    backup_item "$ATOM_CONFIG_DIR" config/caelestia
    LEGACY_BAR_STATUS=true
fi

LEGACY_HYPR_LAUNCHER=false
if [[ $CONFIG_MODE == merge && -d $ATOM_HYPR_DIR ]] && \
        rg -q 'caelestia shell -d|qs -c caelestia kill' "$ATOM_HYPR_DIR"; then
    backup_item "$ATOM_HYPR_DIR" config/hypr
    LEGACY_HYPR_LAUNCHER=true
fi

install_shell_source
install_config_tree "$ROOT/config/caelestia" "$ATOM_CONFIG_DIR" config/caelestia
install_config_tree "$ROOT/config/hypr" "$ATOM_HYPR_DIR" config/hypr

if [[ $LEGACY_BAR_STATUS == true ]]; then
    if [[ $DRY_RUN == true ]]; then
        log "Eski bar.status ayarı v2.3 statusIcons biçimine taşınacak"
    else
        "$ROOT/scripts/migrate-config.sh" "$ATOM_CONFIG_DIR/shell.json"
    fi
fi

if [[ $LEGACY_HYPR_LAUNCHER == true ]]; then
    if [[ $DRY_RUN == true ]]; then
        log "Hyprland shell komutları atomshell başlatıcısına taşınacak"
    else
        "$ROOT/scripts/migrate-hypr.sh" "$ATOM_HYPR_DIR"
    fi
fi

backup_item "$BIN_HOME/atomshell" bin/atomshell
run mkdir -p "$BIN_HOME"
run install -m 0755 "$ROOT/packaging/atomshell" "$BIN_HOME/atomshell"

if [[ -d "$ROOT/config/bin" ]]; then
    for script in "$ROOT/config/bin"/*; do
        [[ -f "$script" ]] || continue
        name=$(basename -- "$script")
        backup_item "$BIN_HOME/$name" "bin/$name"
        run install -m 0755 "$script" "$BIN_HOME/$name"
    done
fi

service_dir=$CONFIG_HOME/systemd/user
if [[ $PROFILE == full ]]; then
    run mkdir -p "$service_dir"
    if [[ -d "$ROOT/config/systemd/user" ]]; then
        for svc in "$ROOT/config/systemd/user"/*.service; do
            [[ -f "$svc" ]] || continue
            sname=$(basename -- "$svc")
            backup_item "$service_dir/$sname" "systemd/user/$sname"
            run install -m 0644 "$svc" "$service_dir/$sname"
        done
    fi
    service_target=$service_dir/atomshell-usb-notify.service
    backup_item "$service_target" systemd/user/atomshell-usb-notify.service
    run install -m 0644 "$ROOT/packaging/systemd/atomshell-usb-notify.service" "$service_target"
    run chmod +x "$ATOM_HYPR_DIR/scripts"/*.sh
    if [[ $DRY_RUN != true ]] && command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload
        systemctl --user enable atomshell-usb-notify.service >/dev/null 2>&1 || \
            warn "USB bildirim servisi etkinleştirilemedi; shell yine çalışacaktır."
    fi
fi

write_manifest "$VERSION" "$RUNTIME"

if [[ :$PATH: != *":$BIN_HOME:"* ]]; then
    warn "$BIN_HOME PATH içinde değil. Shell profilinize şunu ekleyin: export PATH=\"$BIN_HOME:\$PATH\""
fi

log "Kurulum tamamlandı. Yedek: $BACKUP_DIR"
log "Kontrol: $BIN_HOME/atomshell doctor"
log "Başlat:  $BIN_HOME/atomshell restart"

if [[ $DRY_RUN != true && $NON_INTERACTIVE != true && -t 0 && -n ${WAYLAND_DISPLAY:-} ]]; then
    printf '\n'
    if confirm "Atom Shell şimdi başlatılsın mı? / Launch Atom Shell now?" yes; then
        "$BIN_HOME/atomshell" restart || "$BIN_HOME/atomshell" start || true
    fi
fi
