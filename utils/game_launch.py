#!/usr/bin/python3
"""Steam launch wrapper: argv only, rendering changes require a fresh game process."""
import json
import os
import subprocess
import sys
import game_profiles as profiles


def command(profile, argv, caps, output):
    if not argv or not argv[0] or argv[0].startswith("-"):
        raise ValueError("A game command is required after --")
    prefs = profiles.rendering(profile["render"])
    env = dict(os.environ)
    generating = profiles.frame_generation_active(prefs["frameGeneration"])
    capture = generating and (prefs["frameGenerationSource"] == "compositor"
        or (prefs["frameGenerationSource"] == "auto" and env.get("PROTON_USE_WINED3D") == "1"))
    fg_env = dict(DISABLE_LSFGVK="1", DISABLE_KETTLE_FG="1")
    if generating:
        if not caps["frameGeneration"]:
            raise ValueError("Frame generation is not installed")
        if caps.get("frameGenerationEngine") == "kettle":
            if prefs["frameGeneration"] > 3:
                raise ValueError("Kettle frame generation supports up to 3x")
            fg_env.pop("DISABLE_KETTLE_FG")
            for name in ("MULTIPLIER", "FLOW_SCALE", "FIFO", "LATENCY", "MIN_FPS", "PRESERVE_IMAGES"):
                env.pop("KETTLE_FG_" + name, None)
            fg_env.update(KETTLE_FG="1", KETTLE_FG_CONFIG=str(profiles.framegen_config_path(profile["key"])))
        else:
            if prefs["frameGeneration"] == 0:
                raise ValueError("Automatic frame generation is only available with Kettle")
            fg_env.pop("DISABLE_LSFGVK")
            fg_env.update(LSFGVK_ENV="1", LSFGVK_DLL_PATH=caps["losslessScalingDll"],
                   LSFGVK_MULTIPLIER=str(prefs["frameGeneration"]), LSFGVK_FLOW_SCALE=str(prefs["flowScale"]),
                   LSFGVK_PERFORMANCE_MODE="1" if prefs["performanceMode"] else "0", LSFGVK_PACING_MODE="vsync")
    if prefs["scaler"] == "off" and prefs["fps"] == 0 and not capture:
        env.pop("DISABLE_KETTLE_FG", None)
        env.pop("DISABLE_LSFGVK", None)
        return list(argv), env | fg_env
    if not caps["gamescope"]:
        raise ValueError("Gamescope is required for scaling, FPS limits or OpenGL frame generation")
    width, height = (prefs["output"] if prefs["output"] != "auto" else output).split("x")
    args = ["gamescope", "-W", width, "-H", height]
    if capture:
        args += ["--backend", "sdl"]
    if prefs["scaler"] != "off":
        render_width, render_height = prefs["resolution"].split("x")
        args += ["-w", render_width, "-h", render_height]
        if prefs["scaler"] == "integer":
            args += ["-S", "integer", "-F", "nearest"]
        else:
            args += ["-F", prefs["scaler"]]
        if prefs["scaler"] in ("fsr", "nis"):
            args += ["--sharpness", str(prefs["sharpness"])]
    if prefs["fps"]:
        args += ["-r", str(prefs["fps"])]
    if prefs["unfocusedFps"]:
        args += ["-o", str(prefs["unfocusedFps"])]
    if prefs["fullscreen"]:
        args += ["-f"]
    elif prefs["borderless"]:
        args += ["-b"]
    # ponytail: Gamescope wraps new processes only; live capture needs a separate capture compositor.
    if capture:
        # SDL presents a Vulkan swapchain; the Wayland backend bypasses the layer.
        env.pop("DISABLE_KETTLE_FG", None)
        env.pop("DISABLE_LSFGVK", None)
        child = ["/usr/bin/env", "DISABLE_KETTLE_FG=1", "DISABLE_LSFGVK=1"] + list(argv)
        return args + ["--"] + child, env | fg_env
    # Vulkan games own the layer; avoid generating their frames a second time in Gamescope.
    env.update(DISABLE_KETTLE_FG="1", DISABLE_LSFGVK="1")
    child = ["/usr/bin/env", "-u", "DISABLE_KETTLE_FG", "-u", "DISABLE_LSFGVK"] + [f"{key}={value}" for key, value in fg_env.items()] + list(argv)
    return args + ["--"] + child, env


def monitor_output():
    result = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True, check=True, timeout=8)
    monitors = json.loads(result.stdout)
    monitor = next((item for item in monitors if item.get("focused")), monitors[0])
    return f'{int(monitor["width"])}x{int(monitor["height"])}'


def main():
    try:
        if len(sys.argv) < 4 or sys.argv[2] != "--":
            raise ValueError("Usage: game_launch.py PROFILE -- GAME [ARGUMENTS]")
        key = sys.argv[1]
        profiles.launch_options(key)  # Validate the external profile ID.
        profile = profiles.load()["profiles"].get(key)
        if not profile:
            raise ValueError("Saved game profile was not found")
        prefs = profiles.rendering(profile["render"])
        profiles.write_framegen_config(profile)
        output = monitor_output() if prefs["output"] == "auto" else prefs["output"]
        args, env = command(profile, sys.argv[3:], profiles.capabilities(), output)
        os.execvpe(args[0], args, env)
    except (OSError, ValueError, subprocess.SubprocessError, KeyError, IndexError) as error:
        print(f"Caelestia game profile: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
