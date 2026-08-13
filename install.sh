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
    cat <<'EOF'
Kullanım: ./install.sh [seçenekler]

  --dry-run                 Hiçbir şeyi değiştirmeden yapılacakları göster
  --no-packages             Sistem paketlerine dokunma
  --no-build                Derlenmiş runtime'ı değiştirme
  --non-interactive         Soruları güvenli varsayımlarla geç
  --config-mode MODE        merge (varsayılan), replace veya skip
  --profile PROFILE         full (varsayılan) veya minimal
  --runtime MODE            auto, native veya nix
  --install-nix             Eksikse resmi Nix kurucusunu çalıştır
  -h, --help                Bu yardımı göster
EOF
}

while (($#)); do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        --no-packages) INSTALL_PACKAGES=false ;;
        --no-build) BUILD_RUNTIME=false ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        --config-mode) shift; CONFIG_MODE=${1:-} ;;
        --profile) shift; PROFILE=${1:-} ;;
        --runtime) shift; RUNTIME=${1:-} ;;
        --install-nix) INSTALL_NIX=true ;;
        -h|--help) usage; exit 0 ;;
        *) die "Bilinmeyen seçenek: $1" ;;
    esac
    shift
done

[[ $CONFIG_MODE =~ ^(merge|replace|skip)$ ]] || die "Geçersiz --config-mode: $CONFIG_MODE"
[[ $PROFILE =~ ^(minimal|full)$ ]] || die "Geçersiz --profile: $PROFILE"
[[ $RUNTIME =~ ^(auto|native|nix)$ ]] || die "Geçersiz --runtime: $RUNTIME"
export DRY_RUN NON_INTERACTIVE PROFILE

ensure_user
detect_distro
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
    [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]] && \
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
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
    for dir in assets components modules services utils; do
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

service_target=$CONFIG_HOME/systemd/user/atomshell-usb-notify.service
if [[ $PROFILE == full ]]; then
    backup_item "$service_target" systemd/user/atomshell-usb-notify.service
    run mkdir -p "$(dirname -- "$service_target")"
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
