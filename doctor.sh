#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"

errors=0
warnings=0

ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[1;31m[HATA]\033[0m %s\n' "$*"; errors=$((errors + 1)); }
note() { printf '\033[1;33m[UYARI]\033[0m %s\n' "$*"; warnings=$((warnings + 1)); }

detect_distro
printf 'Atom Shell doktoru — %s (%s)\n\n' "$DISTRO_ID" "$DISTRO_FAMILY"

for command in qs jq rsync nmcli hyprctl; do
    if command -v "$command" >/dev/null 2>&1; then
        ok "$command: $(command -v "$command")"
    else
        bad "$command bulunamadı"
    fi
done

for command in caelestia bluetoothctl wpctl notify-send brightnessctl ddcutil; do
    if command -v "$command" >/dev/null 2>&1; then
        ok "$command kullanılabilir"
    else
        note "$command bulunamadı; ilgili özellik devre dışı kalabilir"
    fi
done

if command -v hyprctl >/dev/null 2>&1; then
    hypr_version=$(hyprctl version 2>/dev/null | sed -nE 's/.*[Vv]ersion[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1)
    [[ -n $hypr_version ]] || hypr_version=$(hyprctl version 2>/dev/null | sed -nE '1s/.*v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
    if [[ -n $hypr_version ]] && version_ge "$hypr_version" 0.55.0; then
        ok "Hyprland $hypr_version (Lua yapılandırma desteği var)"
    else
        bad "Hyprland 0.55.0 veya daha yeni olmalı; bulunan: ${hypr_version:-bilinmiyor}"
    fi
fi

if [[ -f $ATOM_SHELL_DIR/shell.qml ]]; then
    ok "Shell kaynağı: $ATOM_SHELL_DIR"
else
    bad "Shell kaynağı kurulu değil: $ATOM_SHELL_DIR"
fi

if [[ -x $BIN_HOME/atomshell ]]; then
    ok "Yönetim komutu: $BIN_HOME/atomshell"
else
    bad "atomshell komutu kurulu değil"
fi

if command -v atomshell-runtime >/dev/null 2>&1; then
    ok "Nix runtime bulundu"
elif [[ -d $ATOM_RUNTIME_DIR/lib/qt6/qml/Caelestia ]]; then
    ok "Yerel QML runtime bulundu"
else
    bad "Atom Shell QML eklenti runtime'ı bulunamadı"
fi

json_errors=0
while IFS= read -r -d '' file; do
    if ! jq empty "$file" >/dev/null 2>&1; then
        bad "Geçersiz JSON: $file"
        json_errors=$((json_errors + 1))
    fi
done < <(find "$ATOM_CONFIG_DIR" -type f -name '*.json' -print0 2>/dev/null)
((json_errors == 0)) && ok "Kullanıcı JSON yapılandırmaları geçerli"

if [[ -r $ATOM_MANIFEST ]]; then
    ok "Kurulum kaydı mevcut"
else
    note "Kurulum kaydı yok; kaynak dizinden kurucu çalıştırılmamış olabilir"
fi

if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
    ok "Wayland oturumu: $WAYLAND_DISPLAY"
else
    note "Aktif Wayland oturumu algılanmadı; görsel çalışma testi yapılmadı"
fi

printf '\nSonuç: %d hata, %d uyarı.\n' "$errors" "$warnings"
((errors == 0))
