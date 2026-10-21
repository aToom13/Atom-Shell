#!/usr/bin/env python3
"""Native locale/time controls and persistent Hyprland keyboard settings."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def run(*args):
    return subprocess.run(args, capture_output=True, check=True, text=True, timeout=120).stdout.strip()


def keyboard_text(layout, variant):
    tree = ET.parse("/usr/share/X11/xkb/rules/evdev.xml")
    layouts = {node.findtext("configItem/name"): {item.findtext("configItem/name") for item in node.findall("variantList/variant")} for node in tree.findall("layoutList/layout")}
    names, variants = layout.split(","), variant.split(",") if variant else []
    if not 1 <= len(names) <= 4 or any(name not in layouts for name in names) or len(variants) > len(names):
        raise ValueError("Choose up to four valid keyboard layout codes, e.g. tr,us")
    if any(value and value not in layouts[name] for name, value in zip(names, variants)):
        raise ValueError("Keyboard variant does not match the layout")
    return "-- Managed by Nexus > Language & region\nhl.config({input={kb_layout=" + json.dumps(layout) + ",kb_variant=" + json.dumps(variant) + "}})\n"


def main(args):
    action, *values = args
    if action == "choices":
        print(json.dumps({"locales": run("localectl", "list-locales").splitlines(),
                          "layout": json.loads(run("hyprctl", "-j", "getoption", "input:kb_layout")).get("str", ""),
                          "variant": json.loads(run("hyprctl", "-j", "getoption", "input:kb_variant")).get("str", "").replace("[[EMPTY]]", "")}))
    elif action == "locale" and len(values) == 1:
        if values[0] not in run("localectl", "list-locales").splitlines():
            raise ValueError("Choose an installed locale")
        run("localectl", "set-locale", "LANG=" + values[0])
    elif action == "timezone" and len(values) == 1:
        if values[0] not in run("timedatectl", "list-timezones").splitlines():
            raise ValueError("Choose a valid time zone, e.g. Europe/Tirane")
        run("timedatectl", "set-timezone", values[0])
    elif action == "ntp" and values in (["true"], ["false"]):
        run("timedatectl", "set-ntp", values[0])
    elif action == "keyboard" and len(values) == 2:
        content = keyboard_text(*values)
        directory = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "caelestia"
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / "keyboard-overrides.lua"
        old = path.read_bytes() if path.exists() else b""
        with tempfile.NamedTemporaryFile(mode="w", dir=directory, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)
        try:
            run("luac", "-p", str(temporary))
            temporary.replace(path)
            try:
                run("hyprctl", "reload")
                if run("hyprctl", "configerrors"):
                    raise ValueError("Hyprland reported a configuration error")
            except (ValueError, subprocess.SubprocessError):
                path.write_bytes(old)
                run("hyprctl", "reload")
                raise
        finally:
            temporary.unlink(missing_ok=True)
    else:
        raise ValueError("Unknown region action")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, IndexError, subprocess.SubprocessError) as error:
        print(getattr(error, "stderr", None) or str(error), file=sys.stderr)
        sys.exit(1)
