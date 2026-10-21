#!/usr/bin/python3
"""Capture an existing application; never changes its process or launcher."""
import os
import json
import math
import re
import shutil
import sys
import subprocess
from pathlib import Path
import game_profiles as profiles


def command(profile, windows, caps, monitors=()):
    profiles.launch_options(profile["key"])
    prefs = profiles.rendering(profile["render"])
    if not profiles.frame_generation_active(prefs["frameGeneration"]):
        raise ValueError("Choose automatic, 2x or 3x frame generation first")
    if not caps["frameGeneration"] or caps.get("frameGenerationEngine") != "kettle":
        raise ValueError("Live capture requires Kettle frame generation")
    if prefs["frameGeneration"] > 3:
        raise ValueError("Live capture supports up to 3x")
    window = next((w for w in windows if w["key"] == profile["key"]), None)
    if not window:
        raise ValueError("The selected application is not running; refresh the list")
    address = window["address"]
    if not re.fullmatch(r"0x[0-9a-fA-F]+", address):
        raise ValueError("Invalid capture window address")
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(("KETTLE_FG", "LSFGVK_")) or key in ("DISABLE_KETTLE_FG", "VK_INSTANCE_LAYERS"):
            env.pop(key)
    env.update(QSG_RHI_BACKEND="vulkan", QSG_RENDER_LOOP="basic", QSG_RHI_FRAMES_IN_FLIGHT="1",
               KETTLE_FG="1", KETTLE_FG_CONFIG=str(profiles.framegen_config_path(profile["key"])),
               # Qt's three swapchain images leave room for only one generated frame.
               KETTLE_FG_PRESERVE_IMAGES="false", KETTLE_FG_STATS="true", DISABLE_LSFGVK="1", CAELESTIA_CAPTURE_ADDRESS=address)
    monitor = next((m for m in monitors if m.get("id") == window.get("monitor")), None)
    if monitor:
        refresh = float(monitor.get("refreshRate", 0))
        if not math.isfinite(refresh) or refresh <= 0:
            raise ValueError("Invalid capture monitor refresh rate")
        env["KETTLE_FG_REFRESH"] = str(refresh)
    return ["qs", "-n", "-p", str(Path(__file__).with_name("capture") / "shell.qml"), "--no-color"], env


def main():
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: game_capture.py PROFILE")
        profiles.launch_options(sys.argv[1])
        profile = profiles.load()["profiles"].get(sys.argv[1])
        if not profile:
            raise ValueError("Saved application profile was not found")
        if not shutil.which("qs"):
            raise ValueError("Quickshell is required for live capture")
        monitors = json.loads(subprocess.run(["hyprctl", "-j", "monitors"], check=True,
                              capture_output=True, text=True, timeout=8).stdout)
        argv, env = command(profile, profiles.running_windows(), profiles.capabilities(), monitors)
        profiles.write_framegen_config(profile)
        selector = json.dumps("address:" + env["CAELESTIA_CAPTURE_ADDRESS"])
        subprocess.run(["hyprctl", "eval", "(function() local w=hl.get_window(" + selector
                        + "); assert(w); hl.dispatch(hl.dsp.focus({window=w})) end)()"],
                       check=True, capture_output=True, text=True, timeout=8)
        os.execvpe(argv[0], argv, env)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"Caelestia live capture: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
