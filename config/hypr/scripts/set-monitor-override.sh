#!/usr/bin/env bash
set -euo pipefail

output=${1-}
mode=${2-}
position=${3-}
scale=${4-}
transform=${5-0}
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/caelestia
overrides=$config_dir/monitor-overrides.tsv
tmp_file=$(mktemp "$config_dir/.monitor-overrides.XXXXXX")

if [[ -z $output || $output == *$'\t'* || $output == *$'\n'* ]]; then
    exit 2
fi
if [[ ! $mode =~ ^[0-9]+x[0-9]+@[0-9]+([.][0-9]+)?$ && $mode != preferred ]]; then
    exit 2
fi
if [[ ! $position =~ ^-?[0-9]+x-?[0-9]+$ && $position != auto ]]; then
    exit 2
fi
if [[ ! $scale =~ ^(1|1\.25|1\.5|1\.75|2)$ || ! $transform =~ ^[0-7]$ ]]; then
    exit 2
fi

mkdir -p "$config_dir"
if [[ -f $overrides ]]; then
    awk -F '\t' -v name="$output" '$1 != name' "$overrides" > "$tmp_file"
fi
printf '%s\t%s\t%s\t%s\t%s\n' "$output" "$mode" "$position" "$scale" "$transform" >> "$tmp_file"
mv "$tmp_file" "$overrides"
hyprctl reload >/dev/null
