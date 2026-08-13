#!/usr/bin/env bash

if [[ -n ${ATOM_SHELL_COMMON_LOADED:-} ]]; then
    return 0
fi
readonly ATOM_SHELL_COMMON_LOADED=1

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
BIN_HOME=${ATOM_SHELL_BIN_HOME:-$HOME/.local/bin}
ATOM_DATA_DIR=$DATA_HOME/atomshell
ATOM_RUNTIME_DIR=$ATOM_DATA_DIR/runtime
ATOM_SHELL_DIR=$CONFIG_HOME/quickshell/caelestia
ATOM_CONFIG_DIR=$CONFIG_HOME/caelestia
ATOM_HYPR_DIR=$CONFIG_HOME/hypr
ATOM_STATE_DIR=$STATE_HOME/atomshell
ATOM_MANIFEST=$ATOM_DATA_DIR/install.env
DRY_RUN=${DRY_RUN:-false}

log() { printf '\033[1;36m[Atom Shell]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[Atom Shell]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[Atom Shell]\033[0m %s\n' "$*" >&2; exit 1; }

quote_cmd() {
    local arg
    printf '  '
    printf '%q ' "$@"
    printf '\n'
}

run() {
    if [[ $DRY_RUN == true ]]; then
        quote_cmd "$@"
    else
        "$@"
    fi
}

run_root() {
    if (( EUID == 0 )); then
        run "$@"
    elif command -v sudo >/dev/null 2>&1; then
        run sudo "$@"
    else
        die "Bu işlem için sudo gerekiyor: $*"
    fi
}

confirm() {
    local prompt=$1 default=${2:-no} answer
    if [[ ${NON_INTERACTIVE:-false} == true ]]; then
        [[ $default == yes ]]
        return
    fi
    if [[ $default == yes ]]; then
        read -r -p "$prompt [E/h] " answer
        [[ -z $answer || $answer =~ ^[EeYy]$ ]]
    else
        read -r -p "$prompt [e/H] " answer
        [[ $answer =~ ^[EeYy]$ ]]
    fi
}

new_backup() {
    local stamp candidate suffix=0
    stamp=$(date +%Y%m%d-%H%M%S)
    candidate=$ATOM_STATE_DIR/backups/$stamp
    while [[ -e $candidate || -L $candidate ]]; do
        suffix=$((suffix + 1))
        candidate=$ATOM_STATE_DIR/backups/$stamp-$suffix
    done
    BACKUP_DIR=$candidate
    export BACKUP_DIR
    run mkdir -p "$BACKUP_DIR"
}

backup_item() {
    local source=$1 label=$2
    [[ -e $source || -L $source ]] || return 0
    [[ -n ${BACKUP_DIR:-} ]] || new_backup
    log "Yedekleniyor: $source"
    run mkdir -p "$BACKUP_DIR/$(dirname -- "$label")"
    run cp -a -- "$source" "$BACKUP_DIR/$label"
}

version_ge() {
    local current=$1 minimum=$2
    [[ $(printf '%s\n%s\n' "$minimum" "$current" | sort -V | head -n1) == "$minimum" ]]
}

detect_distro() {
    DISTRO_ID=unknown
    DISTRO_LIKE=
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        DISTRO_ID=${ID:-unknown}
        DISTRO_LIKE=${ID_LIKE:-}
    fi
    if [[ $DISTRO_ID == arch || $DISTRO_ID == cachyos || " $DISTRO_LIKE " == *" arch "* ]]; then
        DISTRO_FAMILY=arch
    elif [[ $DISTRO_ID =~ ^(debian|ubuntu|linuxmint)$ || " $DISTRO_LIKE " == *" debian "* || " $DISTRO_LIKE " == *" ubuntu "* ]]; then
        DISTRO_FAMILY=debian
    else
        DISTRO_FAMILY=unknown
    fi
    export DISTRO_ID DISTRO_LIKE DISTRO_FAMILY
}

ensure_user() {
    (( EUID != 0 )) || die "Kurucuyu root olarak çalıştırmayın; gerektiğinde sudo kendisi çağrılır."
    [[ -n ${HOME:-} && $HOME != / ]] || die "Geçerli bir kullanıcı HOME dizini bulunamadı."
}

write_manifest() {
    local version=$1 runtime=$2
    run mkdir -p "$ATOM_DATA_DIR"
    if [[ $DRY_RUN == true ]]; then
        log "Kurulum kaydı yazılacak: $ATOM_MANIFEST"
        return
    fi
    {
        printf 'ATOM_SHELL_VERSION=%q\n' "$version"
        printf 'ATOM_SHELL_RUNTIME=%q\n' "$runtime"
        printf 'ATOM_SHELL_SOURCE=%q\n' "$PROJECT_ROOT"
        printf 'ATOM_SHELL_INSTALLED_AT=%q\n' "$(date --iso-8601=seconds)"
    } > "$ATOM_MANIFEST"
}
