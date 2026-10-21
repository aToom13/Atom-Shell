#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
binary="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia/game-fps"
if [ ! -x "$binary" ] || [ "$source_dir/game_fps.cpp" -nt "$binary" ]; then
    mkdir -p "$(dirname -- "$binary")"
    trap 'rm -f "$binary.tmp.$$"' EXIT
    c++ -std=c++20 -O2 "$source_dir/game_fps.cpp" -o "$binary.tmp.$$" -lXpresent -lX11
    mv -f "$binary.tmp.$$" "$binary"
fi
exec "$binary" "$@"
