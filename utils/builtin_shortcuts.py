"""Change registered Hyprland shortcuts without replacing their actions."""
import ctypes
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

DIRECTORY = Path.home() / ".config/caelestia"
MODIFIERS = {"SUPER", "CTRL", "ALT", "SHIFT"}


def canonical(keys):
    parts = [part.strip().lower() for part in keys.split("+")]
    return "+".join(sorted(parts[:-1]) + parts[-1:])


def validate(keys):
    if not isinstance(keys, str) or len(keys) > 160:
        raise ValueError("Enter a key combination, e.g. SUPER + SHIFT + T")
    parts = [part.strip() for part in keys.split("+")]
    mods = [part.upper() for part in parts[:-1]]
    key = parts[-1]
    if any(mod not in MODIFIERS for mod in mods) or len(set(mods)) != len(mods):
        raise ValueError("Use SUPER, CTRL, ALT and SHIFT once each")
    if not re.fullmatch(r"[A-Za-z0-9_]+|mouse:[0-9]+|code:[0-9]+", key):
        raise ValueError("Use a key name, e.g. T, space, Return, minus or mouse:272")
    library = ctypes.CDLL("libxkbcommon.so.0")
    library.xkb_keysym_from_name.argtypes = [ctypes.c_char_p, ctypes.c_int]
    if not (re.fullmatch(r"(mouse|code):[0-9]+", key) or key.lower() in {"mouse_up", "mouse_down"}
            or library.xkb_keysym_from_name(key.encode(), 1)):
        raise ValueError("Unknown key name: " + key)
    return " + ".join(mods + [key])


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True, timeout=15).stdout.strip()


def registry():
    code = '(function() local rows={} for _,v in pairs(_G.nexusKeybinds or {}) do table.insert(rows,v.original .. "\\t" .. v.key) end table.sort(rows) return table.concat(rows,"\\n") end)()'
    output = run("hyprctl", "repl", code)
    if not output:
        raise ValueError("Shortcut registry unavailable; reload the Hyprland configuration")
    return [{"original": fields[0], "key": fields[1], "changed": canonical(fields[0]) != canonical(fields[1])}
            for line in output.splitlines() if len(fields := line.split("\t")) == 2]


def atomic_write(path, content):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content)
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def update(original, target, reset=False):
    original = validate(original)
    target = validate(original if reset else target)
    bindings = registry()
    identity = canonical(original)
    if not any(canonical(binding["original"]) == identity for binding in bindings):
        raise ValueError("This shortcut is no longer registered; reopen the editor")
    for binding in bindings:
        if canonical(binding["original"]) != identity and canonical(binding["key"]) == canonical(target):
            raise ValueError("Key combination already used: " + binding["key"])
    # Include bindings added outside the managed configuration.
    masks = {"SHIFT": 1, "CTRL": 4, "ALT": 8, "SUPER": 64}
    parts = target.split(" + ")
    mask = sum(masks[mod] for mod in parts[:-1])
    current = next(binding["key"] for binding in bindings if canonical(binding["original"]) == identity)
    if canonical(current) != canonical(target):
        for binding in json.loads(run("hyprctl", "-j", "binds")):
            if binding["modmask"] == mask and binding["key"].lower() == parts[-1].lower():
                raise ValueError("Key combination already used: " + target)
    state_path = DIRECTORY / "keybind-overrides.json"
    lua_path = DIRECTORY / "keybind-overrides.lua"
    old = {path: path.read_bytes() if path.exists() else None for path in (state_path, lua_path)}
    state = json.loads(old[state_path] or b"{}")
    if reset or canonical(target) == identity:
        state.pop(identity, None)
    else:
        state[identity] = target
    lua = "-- Managed by Nexus > Keyboard shortcuts\nreturn {\n" + "".join(
        "    [" + json.dumps(key) + "] = " + json.dumps(value) + ",\n" for key, value in sorted(state.items())) + "}\n"
    try:
        atomic_write(lua_path, lua.encode())
        run("luac", "-p", str(lua_path))
        atomic_write(state_path, (json.dumps(state, indent=2) + "\n").encode())
        run("hyprctl", "reload")
        errors = run("hyprctl", "configerrors")
        if errors:
            raise ValueError(errors)
        updated = registry()
        if not any(canonical(item["original"]) == identity and canonical(item["key"]) == canonical(target) for item in updated):
            raise ValueError("Shortcut did not apply")
    except Exception:
        for path, content in old.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, content)
        run("hyprctl", "reload")
        raise


def main(args):
    if args == ["list"]:
        print(json.dumps(registry()))
    elif len(args) in (2, 3) and args[0] in {"set", "reset"}:
        if (args[0] == "set" and len(args) != 3) or (args[0] == "reset" and len(args) != 2):
            raise ValueError("Invalid shortcut arguments")
        DIRECTORY.mkdir(parents=True, exist_ok=True)
        with (DIRECTORY / ".keybind-editor.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            update(args[1], args[2] if len(args) == 3 else "", args[0] == "reset")
    else:
        raise ValueError("Usage: builtin_shortcuts.py list | set ORIGINAL KEY | reset ORIGINAL")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(getattr(error, "stderr", None) or str(error), file=sys.stderr)
        sys.exit(1)
