#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"

DRY_RUN=false
NON_INTERACTIVE=false
PURGE_CONFIG=false

while (($#)); do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        --purge-config) PURGE_CONFIG=true ;;
        -h|--help)
            printf 'Kullanım: ./uninstall.sh [--dry-run] [--non-interactive] [--purge-config]\n'
            exit 0
            ;;
        *) die "Bilinmeyen seçenek: $1" ;;
    esac
    shift
done
export DRY_RUN NON_INTERACTIVE
ensure_user

if [[ $NON_INTERACTIVE != true ]]; then
    confirm "Atom Shell kaldırılsın mı? Dosyalar önce yedeklenecek." no || exit 0
fi

new_backup
command -v atomshell >/dev/null 2>&1 && atomshell stop || true

service_target=$CONFIG_HOME/systemd/user/atomshell-usb-notify.service
SERVICE_INSTALLED=false
[[ -e $service_target || -L $service_target ]] && SERVICE_INSTALLED=true

backup_item "$ATOM_SHELL_DIR" quickshell/caelestia
backup_item "$ATOM_RUNTIME_DIR" atomshell/runtime
backup_item "$ATOM_MANIFEST" atomshell/install.env
backup_item "$BIN_HOME/atomshell" bin/atomshell
backup_item "$service_target" systemd/user/atomshell-usb-notify.service

if [[ $DRY_RUN != true && $SERVICE_INSTALLED == true ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now atomshell-usb-notify.service >/dev/null 2>&1 || true
fi

run rm -rf -- "$ATOM_SHELL_DIR" "$ATOM_RUNTIME_DIR"
run rm -f -- "$ATOM_MANIFEST" "$BIN_HOME/atomshell" "$service_target"

if [[ $PURGE_CONFIG == true ]]; then
    backup_item "$ATOM_CONFIG_DIR" config/caelestia
    backup_item "$ATOM_HYPR_DIR" config/hypr
    run rm -rf -- "$ATOM_CONFIG_DIR" "$ATOM_HYPR_DIR"
else
    log "Kullanıcı ayarları korundu. Tam kaldırma için --purge-config kullanılabilir."
fi

log "Atom Shell kaldırıldı. Kurtarma yedeği: $BACKUP_DIR"
log "Kurucunun yüklediği sistem paketleri bilerek kaldırılmadı."
