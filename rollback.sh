#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"

DRY_RUN=false
if [[ ${1:-} == --dry-run ]]; then
    DRY_RUN=true
    shift
fi
export DRY_RUN

if [[ -z ${1:-} ]]; then
    printf 'Kullanım: ./rollback.sh [--dry-run] YEDEK_DİZİNİ\n\nMevcut yedekler:\n'
    find "$ATOM_STATE_DIR/backups" -mindepth 1 -maxdepth 1 -type d -printf '  %p\n' 2>/dev/null | sort -r | head -n 10
    exit 2
fi

backup=$1
[[ -d $backup ]] || die "Yedek dizini bulunamadı: $backup"
case $(cd -- "$backup" && pwd -P) in
    "$ATOM_STATE_DIR"/backups/*) ;;
    *) die "Yalnızca Atom Shell yedek dizinleri geri yüklenebilir." ;;
esac

new_backup
log "Mevcut kurulum önce şuraya yedekleniyor: $BACKUP_DIR"

restore_one() {
    local relative=$1 target=$2 current_label=$3
    [[ -e $backup/$relative || -L $backup/$relative ]] || return 0
    backup_item "$target" "$current_label"
    run rm -rf -- "$target"
    run mkdir -p "$(dirname -- "$target")"
    run cp -a -- "$backup/$relative" "$target"
    log "Geri yüklendi: $target"
}

restore_one quickshell/caelestia "$ATOM_SHELL_DIR" quickshell/caelestia
restore_one atomshell/runtime "$ATOM_RUNTIME_DIR" atomshell/runtime
restore_one atomshell/install.env "$ATOM_MANIFEST" atomshell/install.env
restore_one bin/atomshell "$BIN_HOME/atomshell" bin/atomshell
restore_one config/caelestia "$ATOM_CONFIG_DIR" config/caelestia
restore_one config/hypr "$ATOM_HYPR_DIR" config/hypr
restore_one systemd/user/atomshell-usb-notify.service "$CONFIG_HOME/systemd/user/atomshell-usb-notify.service" systemd/user/atomshell-usb-notify.service

if [[ $DRY_RUN != true ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
fi
log "Geri alma tamamlandı."
