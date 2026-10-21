#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$ROOT"

printf '[1/9] Bash sözdizimi\n'
while IFS= read -r -d '' file; do
    bash -n "$file"
done < <(find . -type f -name '*.sh' -not -path './.git/*' -not -path './.build/*' -print0)

printf '[2/9] JSON geçerliliği\n'
while IFS= read -r -d '' file; do
    jq empty "$file"
done < <(find config .github -type f -name '*.json' -print0)

printf '[3/9] Lua sözdizimi\n'
if command -v luac >/dev/null 2>&1; then
    while IFS= read -r -d '' file; do
        luac -p "$file"
    done < <(find config -type f -name '*.lua' -print0)
else
    printf '  luac yok; atlandı\n'
fi

printf '[4/9] Taşınabilirlik ve merge işaretleri\n'
if rg -n '/home/atom13|\batom13\b|weatherLocation"[[:space:]]*:[[:space:]]*"Ankara"' \
    --glob '!tests/smoke.sh' --glob '!.git/**' .; then
    printf 'Kullanıcıya özel değer bulundu.\n' >&2
    exit 1
fi
if rg -n '^(<<<<<<<|=======|>>>>>>>)' --glob '!.git/**' .; then
    printf 'Çözülmemiş merge işareti bulundu.\n' >&2
    exit 1
fi

printf '[5/9] v2.3 yapılandırma API kontrolü\n'
if rg -n '"status"[[:space:]]*:|Config\.bar\.entries\.(find|map)|Config\.bar\.entries\.length|GlobalConfig\.bar\.entries[[:space:]]*=|GlobalConfig\.utilities\.quickToggles[[:space:]]*=' \
    config modules --glob '*.json' --glob '*.qml'; then
    printf 'Eski v2.2 yapılandırma API kullanımı bulundu.\n' >&2
    exit 1
fi

printf '[6/9] v2.2 yapılandırma geçişi\n'
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
cp tests/fixtures/shell-v2.2.json "$test_root/shell.json"
scripts/migrate-config.sh "$test_root/shell.json" >/dev/null

mkdir -p "$test_root/hypr/hyprland"
cp tests/fixtures/hypr/execs.lua "$test_root/hypr/hyprland/execs.lua"
cp tests/fixtures/hypr/keybinds.lua "$test_root/hypr/hyprland/keybinds.lua"
scripts/migrate-hypr.sh "$test_root/hypr" >/dev/null
rg -q 'atomshell start' "$test_root/hypr/hyprland/execs.lua"
rg -q 'atomshell start' "$test_root/hypr/hyprland/keybinds.lua"
rg -q 'atomshell stop' "$test_root/hypr/hyprland/keybinds.lua"
rg -q 'atomshell restart' "$test_root/hypr/hyprland/keybinds.lua"
if rg -q 'caelestia shell -d|qs -c caelestia kill' "$test_root/hypr"; then
    printf 'Eski Hyprland shell başlatıcısı taşınamadı.\n' >&2
    exit 1
fi
jq -e '
    (.bar | has("status") | not)
    and (.bar.statusIcons | map(select(.id == "audio"))[0].enabled == false)
    and (.bar.statusIcons | map(select(.id == "microphone"))[0].enabled == false)
    and (.bar.statusIcons | map(select(.id == "kbLayout"))[0].enabled == true)
' "$test_root/shell.json" >/dev/null
scripts/migrate-config.sh "$test_root/shell.json" >/dev/null

version=$(<VERSION)
rg -q "readonly property string version: \"${version}\"" utils/AtomInfo.qml || {
    printf 'VERSION ile About sürümü eşleşmiyor.\n' >&2
    exit 1
}

(
    export HOME="$test_root/home"
    export XDG_STATE_HOME="$test_root/state"
    export DRY_RUN=false
    # shellcheck source=scripts/lib/common.sh
    source scripts/lib/common.sh
    new_backup
    first_backup=$BACKUP_DIR
    new_backup
    [[ $first_backup != "$BACKUP_DIR" ]]
)

printf '[7/9] Çift dilli belgeler\n'
for pair in \
    'README.md README.tr.md' \
    'CONTRIBUTING.md CONTRIBUTING.tr.md' \
    'SECURITY.md SECURITY.tr.md' \
    'docs/ARCHITECTURE.md docs/ARCHITECTURE.tr.md' \
    'docs/DISTROS.md docs/DISTROS.tr.md' \
    'docs/nexus.md docs/nexus.tr.md' \
    'docs/game-mode.md docs/game-mode.tr.md' \
    'docs/phone-tailscale.md docs/phone-tailscale.tr.md' \
    'docs/shortcuts.md docs/shortcuts.tr.md'; do
    read -r english turkish <<< "$pair"
    [[ -s $english && -s $turkish ]] || {
        printf 'Belge dil çifti eksik: %s / %s\n' "$english" "$turkish" >&2
        exit 1
    }
    rg -q 'Türkçe' "$english"
    rg -q 'English' "$turkish"
done

printf '[8/9] Kurucu dry-run\n'
rm -rf -- "$test_root"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/home"
env HOME="$test_root/home" \
    XDG_CONFIG_HOME="$test_root/config" \
    XDG_DATA_HOME="$test_root/data" \
    XDG_STATE_HOME="$test_root/state" \
    ATOM_SHELL_BIN_HOME="$test_root/bin" \
    "$ROOT/install.sh" --dry-run --no-packages --no-build --non-interactive --config-mode replace >/dev/null
[[ -z $(find "$test_root" -mindepth 1 -not -path "$test_root/home" -print -quit) ]] || {
    printf 'Dry-run dosya oluşturdu.\n' >&2
    exit 1
}

printf '[9/9] Git whitespace ve isteğe bağlı ShellCheck\n'
git diff --check
if command -v shellcheck >/dev/null 2>&1; then
    mapfile -d '' scripts < <(find . -type f -name '*.sh' -not -path './.git/*' -not -path './.build/*' -print0)
    shellcheck -x "${scripts[@]}"
else
    printf '  shellcheck yok; atlandı\n'
fi

printf 'Smoke test başarılı.\n'
