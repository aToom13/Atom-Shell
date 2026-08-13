#!/usr/bin/env bash
set -euo pipefail

cache_root="/var/cache/hyprpm/$(id -un)"
state_file="$cache_root/state.toml"

current_abi() {
    hyprctl version | sed -n 's/^Version ABI string: //p'
}

cached_abi() {
    sed -n "s/^hash = '\([^']*\)'.*/\1/p" "$state_file" 2>/dev/null || true
}

header_version() {
    pkg-config --modversion hyprland 2>/dev/null || true
}

status() {
    local current cached headers writable loaded
    current=$(current_abi)
    cached=$(cached_abi)
    headers=$(header_version)
    writable=yes
    [[ -d "$cache_root" && ! -w "$cache_root" ]] && writable=no
    loaded=$(hyprctl plugin list 2>/dev/null | sed '/^$/d' | tr '\n' ' ')
    printf 'current\t%s\n' "$current"
    printf 'cached\t%s\n' "$cached"
    printf 'headers\t%s\n' "$headers"
    printf 'writable\t%s\n' "$writable"
    printf 'loaded\t%s\n' "${loaded:-none}"
}

sync_system_headers() {
    local current headers_version stage backup pc_source tmp_state
    current=$(current_abi)
    headers_version=$(header_version)

    [[ -n "$current" ]] || { printf 'Could not read the running Hyprland ABI.\n' >&2; exit 1; }
    [[ -n "$headers_version" && -d /usr/include/hyprland ]] || {
        printf 'The installed Hyprland development headers were not found.\n' >&2
        exit 1
    }

    mkdir -p "$cache_root"
    [[ -w "$cache_root" ]] || {
        printf 'HyprPM cache is not writable: %s\n' "$cache_root" >&2
        printf 'Fix its ownership first, then retry.\n' >&2
        exit 13
    }

    pc_source=$(pkg-config --variable=pcfiledir hyprland)/hyprland.pc
    [[ -f "$pc_source" ]] || { printf 'hyprland.pc was not found.\n' >&2; exit 1; }

    stage=$(mktemp -d "$cache_root/.headersRoot.new.XXXXXX")
    trap 'rm -rf -- "$stage"' EXIT
    mkdir -p "$stage/include" "$stage/share/pkgconfig"

    printf '[1/4] Copying installed Hyprland %s headers…\n' "$headers_version"
    cp -a /usr/include/hyprland "$stage/include/"
    sed "s#^prefix=.*#prefix=$stage/include#" "$pc_source" > "$stage/share/pkgconfig/hyprland.pc"

    printf '[2/4] Replacing stale HyprPM header cache…\n'
    backup="$cache_root/headersRoot.previous"
    rm -rf -- "$backup"
    [[ ! -d "$cache_root/headersRoot" ]] || mv "$cache_root/headersRoot" "$backup"
    mv "$stage" "$cache_root/headersRoot"
    trap - EXIT
    sed -i "s#^prefix=.*#prefix=$cache_root/headersRoot/include#" "$cache_root/headersRoot/share/pkgconfig/hyprland.pc"

    printf '[3/4] Recording the running ABI…\n'
    tmp_state=$(mktemp "$cache_root/.state.toml.XXXXXX")
    if [[ -f "$state_file" ]] && grep -q '^hash = ' "$state_file"; then
        sed "s#^hash = .*#hash = '$current'#" "$state_file" > "$tmp_state"
    else
        printf "[state]\ndont_warn_install = true\nhash = '%s'\n" "$current" > "$tmp_state"
    fi
    mv "$tmp_state" "$state_file"

    printf '[4/4] Header cache now matches the running compositor.\n'
}

repair() {
    printf 'HyprPM repair started.\n'
    sync_system_headers
    printf 'Updating and rebuilding plugin repositories with installed headers…\n'
    rebuild_repositories
    printf 'Loading enabled plugins…\n'
    hyprpm reload
    printf 'Verifying loaded plugins…\n'
    hyprctl plugin list
    printf 'HyprPM repair completed.\n'
}

rebuild_repositories() {
    local requested=${1:-}
    local repo_state repo_dir repo_name repo_url build_dir manifest pin current_commit found=no
    shopt -s nullglob
    for repo_state in "$cache_root"/*/state.toml; do
        repo_dir=${repo_state%/state.toml}
        repo_name=$(sed -n "s/^name = '\([^']*\)'.*/\1/p" "$repo_state" | tail -n 1)
        repo_url=$(sed -n "s/^url = '\([^']*\)'.*/\1/p" "$repo_state" | tail -n 1)
        [[ -n "$repo_name" && -n "$repo_url" ]] || continue
        [[ -z "$requested" || "$repo_name" == "$requested" ]] || continue
        found=yes

        printf 'Repository: %s\n' "$repo_name"
        build_dir=$(mktemp -d "$cache_root/.build-${repo_name}.XXXXXX")
        if ! git clone --quiet --recursive "$repo_url" "$build_dir"; then
            rm -rf -- "$build_dir"
            printf 'Could not clone %s.\n' "$repo_url" >&2
            return 1
        fi

        manifest="$build_dir/hyprpm.toml"
        [[ -f "$manifest" ]] || {
            rm -rf -- "$build_dir"
            printf '%s does not contain hyprpm.toml.\n' "$repo_name" >&2
            return 1
        }

        current_commit=$(hyprctl version | sed -n '1s/.*commit \([0-9a-f]\{40\}\).*/\1/p')
        pin=$(python3 - "$manifest" "$current_commit" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as handle:
    data = tomllib.load(handle)
for pair in data.get("repository", {}).get("commit_pins", []):
    if len(pair) >= 2 and pair[0] == sys.argv[2]:
        print(pair[1])
        break
PY
)
        if [[ -n "$pin" ]]; then
            printf 'Using compatibility pin %s for Hyprland %s.\n' "$pin" "$current_commit"
            git -C "$build_dir" fetch --quiet --depth 1 origin "$pin"
            git -C "$build_dir" checkout --quiet --detach "$pin"
        else
            pin=$(git -C "$build_dir" rev-parse HEAD)
            printf 'No exact compatibility pin; using repository HEAD %s.\n' "$pin"
        fi

        PKG_CONFIG_PATH="$cache_root/headersRoot/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
            python3 - "$manifest" "$build_dir" "$repo_dir" <<'PY'
import os, pathlib, shutil, subprocess, sys, tomllib

manifest, source, destination = map(pathlib.Path, sys.argv[1:])
with manifest.open("rb") as handle:
    data = tomllib.load(handle)

plugins = [(name, spec) for name, spec in data.items()
           if name != "repository" and isinstance(spec, dict) and spec.get("output")]
if not plugins:
    raise SystemExit("No buildable plugins were declared in hyprpm.toml")

for name, spec in plugins:
    print(f"Building {name}…", flush=True)
    for command in spec.get("build", []):
        print(f"  $ {command}", flush=True)
        subprocess.run(command, cwd=source, shell=True, check=True, env=os.environ)
    output = source / spec["output"]
    if not output.is_file():
        raise SystemExit(f"Expected output was not created: {output}")
    target = destination / output.name
    previous = target.with_suffix(target.suffix + ".previous")
    if target.exists():
        shutil.copy2(target, previous)
    shutil.copy2(output, target)
    target.chmod(0o755)
    print(f"Installed {name}: {target}", flush=True)
PY

        sed -i "s#^hash = '.*'#hash = '$pin'#" "$repo_state"
        rm -rf -- "$build_dir"
    done
    [[ -z "$requested" || "$found" == yes ]] || {
        printf 'Plugin repository was not found: %s\n' "$requested" >&2
        return 1
    }
}

case "${1:-status}" in
    status) status ;;
    sync-headers) sync_system_headers ;;
    rebuild) rebuild_repositories "${2:-}" ;;
    repair) repair ;;
    *)
        printf 'usage: %s {status|sync-headers|rebuild|repair}\n' "$0" >&2
        exit 2
        ;;
esac
