#!/usr/bin/python3
"""Saved rendering profiles and running-window discovery; never executes window titles."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "caelestia"
PROFILE_FILE = CONFIG_DIR / "game-profiles.json"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "caelestia"
TEST_KEY = "test-cube"
RENDER_DEFAULTS = dict(scaler="off", resolution="1280x720", output="auto", sharpness=2,
                       fps=0, unfocusedFps=15, fullscreen=True, borderless=True,
                       frameGeneration=1, frameGenerationSource="auto", frameGenerationMinFps=25,
                       frameGenerationLatency="normal", flowScale=0.5, performanceMode=True,
                       hudEnabled=True, hudFps=True, hudCpu=False, hudRam=False, hudTemperature=False,
                       hudPosition="top-right", hudFontSize=16, hudMargin=16)
RESOLUTIONS = {"640x360", "960x540", "1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"}


def frame_generation_active(value):
    """0 is Kettle's automatic multiplier; 1 is off."""
    return value != 1


def load():
    try:
        data = json.loads(PROFILE_FILE.read_text())
    except FileNotFoundError:
        data = {"selected": "", "profiles": {}}
    if not isinstance(data, dict) or not isinstance(data.get("profiles"), dict):
        raise ValueError("Invalid saved game profiles")
    if data.get("selected", "") and data["selected"] not in data["profiles"]:
        raise ValueError("Selected game profile is missing")
    return data


def save(data):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    temp = PROFILE_FILE.with_suffix(".tmp")
    with temp.open("w") as stream:
        os.chmod(temp, 0o600)
        json.dump(data, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    temp.replace(PROFILE_FILE)


def selected(data=None):
    data = data if data is not None else load()
    return data["profiles"].get(data.get("selected", ""))


def steam_id(pid):
    for _ in range(6):
        try:
            env = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
            for name in (b"SteamAppId=", b"STEAM_COMPAT_APP_ID=", b"SteamGameId="):
                for entry in env:
                    if entry.startswith(name):
                        value = entry[len(name):].decode()
                        if value.isdecimal() and 0 < int(value) < 2**32:
                            return value
            stat = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
            pid = int(stat[1])
            if pid <= 1:
                break
        except (OSError, ValueError, IndexError):
            break
    return ""


def running_windows():
    result = subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True, timeout=8, check=True)
    clients = json.loads(result.stdout)
    windows = {}
    for client in clients:
        app_class = str(client.get("initialClass") or client.get("class") or "")[:250]
        if app_class.lower() in {"org.quickshell", "steam", "steamwebhelper"}:
            continue
        pid = int(client.get("pid", 0))
        app_id = steam_id(pid) if pid > 0 else ""
        try:
            executable = str(Path(f"/proc/{pid}/exe").readlink())
        except OSError:
            executable = ""
        if not app_class:
            app_class = Path(executable).name or f"pid-{pid}"
        key = "steam-" + app_id if app_id else "app-" + hashlib.sha256((app_class.lower() + executable).encode()).hexdigest()[:16]
        title = str(client.get("title") or app_class)[:200]
        game = bool(app_id) or app_class.lower().endswith(".exe")
        windows.setdefault(key, dict(key=key, name=title, appClass=app_class, steamId=app_id,
                                     executable=executable, isGame=game, address=str(client.get("address", "")),
                                     monitor=client.get("monitor")))
    return sorted(windows.values(), key=lambda item: (not item["isGame"], item["name"].lower()))


def capabilities():
    roots = [Path.home() / ".local/share/vulkan/implicit_layer.d", Path("/usr/share/vulkan/implicit_layer.d"), Path("/etc/vulkan/implicit_layer.d")]
    layer = any(list(root.glob("*lsfg*.json")) for root in roots)
    kettle = False
    for root in roots:
        for manifest in root.glob("*kettle_framegen.json"):
            try:
                kettle = kettle or Path(json.loads(manifest.read_text())["layer"]["library_path"]).is_file()
            except (OSError, KeyError, ValueError):
                continue
    libraries = [Path.home() / ".local/share/Steam/steamapps", Path.home() / ".steam/steam/steamapps"]
    library_file = Path.home() / ".local/share/Steam/steamapps/libraryfolders.vdf"
    if library_file.exists():
        libraries += [Path(path.replace("\\\\", "\\")) / "steamapps" for path in re.findall(r'"path"\s+"([^"]+)"', library_file.read_text())]
    dll = next((path for library in libraries for path in (library / "common/Lossless Scaling/lsfg-vk.dll",) if path.is_file()), None)
    engine = "kettle" if kettle else "lsfg" if layer and dll is not None else ""
    return dict(gamescope=bool(shutil.which("gamescope")), testCube=bool(shutil.which("vkcube")), frameGeneration=bool(engine),
                liveCapture=bool(kettle and shutil.which("qs") and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")),
                frameGenerationEngine=engine, maxMultiplier=3 if kettle else 4 if engine else 1,
                frameGenerationLayer=layer, losslessScalingDll=str(dll or ""))


def rendering(data):
    if not isinstance(data, dict) or set(data) - RENDER_DEFAULTS.keys():
        raise ValueError("Unknown rendering option")
    result = RENDER_DEFAULTS | data
    if result["scaler"] not in {"off", "fsr", "nis", "integer", "nearest", "linear"}:
        raise ValueError("Unknown scaling filter")
    if result["frameGenerationSource"] not in {"auto", "game", "compositor"}:
        raise ValueError("Unknown frame-generation source")
    if result["frameGenerationLatency"] not in {"normal", "low"}:
        raise ValueError("Unknown frame-generation latency")
    if result["resolution"] not in RESOLUTIONS or result["output"] not in RESOLUTIONS | {"auto"}:
        raise ValueError("Unsupported resolution")
    if result["hudPosition"] not in {"top-left", "top-right", "bottom-left", "bottom-right"}:
        raise ValueError("Invalid HUD position")
    for key, low, high in (("sharpness", 0, 20), ("fps", 0, 360), ("unfocusedFps", 0, 120), ("frameGeneration", 0, 4), ("frameGenerationMinFps", 0, 120), ("hudFontSize", 12, 28), ("hudMargin", 0, 200)):
        if type(result[key]) is not int or not low <= result[key] <= high:
            raise ValueError(f"Invalid {key}")
    if type(result["flowScale"]) not in (int, float) or not 0.25 <= result["flowScale"] <= 1:
        raise ValueError("Invalid motion estimation scale")
    if any(type(result[key]) is not bool for key in ("fullscreen", "borderless", "performanceMode", "hudEnabled", "hudFps", "hudCpu", "hudRam", "hudTemperature")):
        raise ValueError("Invalid rendering switch")
    return result


def launch_options(key):
    if not re.fullmatch(r"(?:steam-\d{1,10}|app-[a-f0-9]{16}|test-cube)", key):
        raise ValueError("Invalid game profile ID")
    launcher = Path(__file__).with_name("game_launch.py")
    return shlex.join(["/usr/bin/python3", str(launcher), key, "--"]) + " %command%"


def framegen_config_path(key):
    launch_options(key)  # Reuse the profile ID trust boundary.
    return STATE_DIR / "framegen" / (key + ".conf")


def write_framegen_config(profile):
    prefs = rendering(profile["render"])
    path = framegen_config_path(profile["key"])
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(".tmp")
    with temp.open("w") as stream:
        os.chmod(temp, 0o600)
        multiplier = "auto" if prefs["frameGeneration"] == 0 else prefs["frameGeneration"]
        stream.write(f'multiplier = {multiplier}\nflow_scale = {prefs["flowScale"]}\n'
                     f'min_fps = {prefs["frameGenerationMinFps"]}\nlatency = {prefs["frameGenerationLatency"]}\nfifo = true\npreserve_images = false\n')
        stream.flush()
        os.fsync(stream.fileno())
    temp.replace(path)


def execute(action, argument=""):
    data = load()
    windows = running_windows()
    if action == "select":
        if argument and argument not in data["profiles"]:
            window = dict(key=TEST_KEY, name="3D test küpü", appClass="vkcube", isGame=True) if argument == TEST_KEY else next((entry for entry in windows if entry["key"] == argument), None)
            if not window:
                raise ValueError("This window is no longer running; refresh the list")
            try:
                mode = json.loads((CONFIG_DIR / "game-mode.json").read_text())
            except FileNotFoundError:
                mode = {}
            data["profiles"][argument] = window | {"render": dict(RENDER_DEFAULTS), "mode": mode}
        data["selected"] = argument
        save(data)
    elif action == "configure":
        profile = selected(data)
        if not profile:
            raise ValueError("Select a running game first")
        updated = rendering(profile["render"] | json.loads(argument))
        if updated["frameGeneration"] > capabilities()["maxMultiplier"]:
            raise ValueError("This frame-generation multiplier is not available")
        profile["render"] = updated
        if frame_generation_active(updated["frameGeneration"]):
            profile.setdefault("mode", {})["allowTearing"] = False
        save(data)
        write_framegen_config(profile)
    elif action != "status":
        raise ValueError("Unknown game profile command")
    profile = selected(data)
    return dict(ok=True, windows=windows, profiles=list(data["profiles"].values()), selected=data.get("selected", ""),
                profile=(profile | {"render": rendering(profile["render"])}) if profile else None,
                capabilities=capabilities(), launchOptions=launch_options(data["selected"]) if profile else "")


def main():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with (STATE_DIR / "game-mode-session.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            if sys.argv[1] == "select":
                try:
                    active = json.loads((STATE_DIR / "game-mode-session.json").read_text()).get("active")
                except FileNotFoundError:
                    active = False
                if active:
                    raise ValueError("Disable Game Mode before selecting another game")
            result = execute(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
        except Exception as error:
            result = dict(ok=False, error=str(error))
        print(json.dumps(result))
        return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
