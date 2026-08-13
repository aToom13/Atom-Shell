#!/usr/bin/env bash
set -euo pipefail

config_file=${1:-${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/shell.json}

[[ -f $config_file ]] || exit 0
jq empty "$config_file"

if ! jq -e '.bar.status? | type == "object"' "$config_file" >/dev/null; then
    exit 0
fi

tmp=$(mktemp "${config_file}.tmp.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT

jq '
    .bar.status as $legacy
    | if (.bar.statusIcons? | type) == "array" then . else
        .bar.statusIcons = [
            {"id": "lockStatus", "enabled": true},
            {"id": "audio", "enabled": (if $legacy | has("showAudio") then $legacy.showAudio else true end)},
            {"id": "microphone", "enabled": (if $legacy | has("showMicrophone") then $legacy.showMicrophone else true end)},
            {"id": "kbLayout", "enabled": (if $legacy | has("showKbLayout") then $legacy.showKbLayout else false end)},
            {"id": "network", "enabled": true},
            {"id": "bluetooth", "enabled": true},
            {"id": "battery", "enabled": true}
        ]
      end
    | del(.bar.status)
' "$config_file" > "$tmp"

chmod --reference="$config_file" "$tmp"
mv -- "$tmp" "$config_file"
trap - EXIT
printf '[Atom Shell] v2.3 bar.status yapılandırması statusIcons biçimine taşındı: %s\n' "$config_file"
