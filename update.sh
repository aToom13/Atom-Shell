#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"

DRY_RUN=false
CHECK_ONLY=false
NON_INTERACTIVE=false

while (($#)); do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        --check) CHECK_ONLY=true ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        -h|--help)
            printf 'Kullanım: ./update.sh [--check] [--dry-run] [--non-interactive]\n'
            exit 0
            ;;
        *) die "Bilinmeyen seçenek: $1" ;;
    esac
    shift
done
export DRY_RUN NON_INTERACTIVE

git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Güncelleme için Git deposu gerekiyor."
[[ -z $(git -C "$ROOT" status --porcelain) ]] || die "Depoda kaydedilmemiş değişiklikler var; güncellemeden önce commit/stash yapın."
remote=origin
git -C "$ROOT" remote get-url "$remote" >/dev/null 2>&1 || die "origin Git remote'u bulunamadı."

log "Yeni sürüm denetleniyor"
git -C "$ROOT" fetch --tags "$remote"
branch=$(git -C "$ROOT" branch --show-current)
[[ -n $branch ]] || die "Detached HEAD güncellenemez."
local_rev=$(git -C "$ROOT" rev-parse HEAD)
remote_rev=$(git -C "$ROOT" rev-parse "$remote/$branch")

if [[ $local_rev == "$remote_rev" ]]; then
    log "Zaten güncel."
    exit 0
fi
if ! git -C "$ROOT" merge-base --is-ancestor "$local_rev" "$remote_rev"; then
    die "Yerel ve uzak geçmiş ayrılmış; otomatik güncelleme güvenli değil."
fi

printf 'Yeni commitler:\n'
git -C "$ROOT" --no-pager log --oneline --decorate "$local_rev..$remote_rev"
[[ $CHECK_ONLY == true ]] && exit 0

if [[ $DRY_RUN == true ]]; then
    log "Fast-forward, test ve yeniden kurulum yapılacak"
    exit 0
fi

git -C "$ROOT" merge --ff-only "$remote/$branch"
"$ROOT/tests/smoke.sh"
exec "$ROOT/install.sh" --no-packages --non-interactive --config-mode merge
