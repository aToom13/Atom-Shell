#!/usr/bin/env bash
set -euo pipefail

hypr_dir=${1:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}
execs_file=$hypr_dir/hyprland/execs.lua
keybinds_file=$hypr_dir/hyprland/keybinds.lua

if [[ -f $execs_file ]]; then
    sed -i 's/hl\.exec_cmd("caelestia shell -d")/hl.exec_cmd("atomshell start")/g' "$execs_file"
fi

if [[ -f $keybinds_file ]]; then
    sed -i \
        -e 's/hl\.dispatch(hl\.dsp\.exec_cmd("caelestia shell -d"))/hl.dispatch(hl.dsp.exec_cmd("atomshell start"))/g' \
        -e 's/hl\.dsp\.exec_cmd("qs -c caelestia kill")/hl.dsp.exec_cmd("atomshell stop")/g' \
        -e 's/hl\.dsp\.exec_cmd("qs -c caelestia kill; sleep \.1; caelestia shell -d")/hl.dsp.exec_cmd("atomshell restart")/g' \
        "$keybinds_file"
fi

printf '[Atom Shell] Hyprland shell başlatma komutları atomshell biçimine taşındı: %s\n' "$hypr_dir"
