#!/usr/bin/env bash
set -euo pipefail

uuid=${1:-}
ssid=${2:-}
[[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ && -n "$ssid" ]] || { printf 'Invalid Wi-Fi profile.\n' >&2; exit 2; }

password=$(nmcli --show-secrets -g 802-11-wireless-security.psk connection show uuid "$uuid")
escape_wifi() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//;/\\;}
    value=${value//,/\\,}
    value=${value//:/\\:}
    value=${value//\"/\\\"}
    printf '%s' "$value"
}

if [[ -n "$password" ]]; then
    printf 'WIFI:T:WPA;S:%s;P:%s;;' "$(escape_wifi "$ssid")" "$(escape_wifi "$password")"
else
    printf 'WIFI:T:nopass;S:%s;;' "$(escape_wifi "$ssid")"
fi | qrencode --type=SVG --inline --level=M --output=-
