#!/usr/bin/python3
"""Transactional Hyprland/TLP settings for Caelestia's Game Mode."""
import fcntl
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time
import game_profiles

DEFAULTS = dict(disableAnimations=True, disableShellAnimations=True,
                disableBlur=True, disableShellBlur=True,
                disableShadows=True, disableShellShadows=True,
                opaqueWindows=True, opaqueShell=True, removeGaps=True,
                squareCorners=True, hideBorders=False, powerProfile="performance",
                pauseWallpaper=True, pauseVisualisers=True, pauseMediaArtwork=True,
                pauseMediaShapes=True, hideDesktopClock=False,
                muteNotifications=True, muteToasts=True,
                inhibitIdle=True, inhibitSleep=True, allowTearing=False, vrr="keep")
PROFILES = {"performance", "balanced", "power-saver"}
ULTRA = DEFAULTS | dict(powerProfile="power-saver", removeGaps=False, squareCorners=False,
                        hideDesktopClock=True, muteNotifications=False, muteToasts=False,
                        inhibitIdle=False, inhibitSleep=False)
ULTRA_HELPER = "/usr/local/libexec/caelestia-ultra-power"
BACKGROUND_UNITS = ("arch-update.service", "psd-resync.service")
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "caelestia/game-mode.json"
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "caelestia/game-mode-session.json"


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=12)
    output = result.stdout.strip()
    if result.returncode or output.lower().startswith("error") or (args[:2] == ("hyprctl", "eval") and output != "ok"):
        raise RuntimeError(f"{args[0]}: {(result.stderr.strip() or output or str(result.returncode))[:700]}")
    return output


def read(path, fallback):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return fallback


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(".tmp")
    with temp.open("w") as stream:
        os.chmod(temp, 0o600)
        json.dump(data, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    temp.replace(path)


def settings(data):
    data = dict(data) if isinstance(data, dict) else data
    if isinstance(data, dict) and "performanceProfile" in data:
        data["powerProfile"] = "performance" if data.pop("performanceProfile") else "keep"
    if not isinstance(data, dict) or set(data) - DEFAULTS.keys():
        raise ValueError("Unknown Game Mode settings")
    if any(type(value) is not bool for key, value in data.items() if key not in ("powerProfile", "vrr")):
        raise ValueError("Game Mode settings must be booleans")
    if data.get("powerProfile", "keep") not in PROFILES | {"keep"}:
        raise ValueError("Unknown power profile")
    if data.get("vrr", "keep") not in {"keep", "off", "always", "fullscreen"}:
        raise ValueError("Unknown VRR setting")
    return DEFAULTS | data


def targets(prefs):
    values = {}
    for flag, options in {
        "disableAnimations": {"animations:enabled": False},
        "disableBlur": {"decoration:blur:enabled": False, "decoration:motion_blur:enabled": False},
        "disableShadows": {"decoration:shadow:enabled": False, "decoration:glow:enabled": False},
        "opaqueWindows": {"decoration:active_opacity": 1.0, "decoration:inactive_opacity": 1.0},
        "removeGaps": {"general:gaps_in": "0 0 0 0", "general:gaps_out": "0 0 0 0"},
        "squareCorners": {"decoration:rounding": 0},
        "hideBorders": {"general:border_size": 0},
        "allowTearing": {"general:allow_tearing": True},
    }.items():
        if prefs[flag]:
            values.update(options)
    if prefs["vrr"] != "keep":
        values["misc:vrr"] = {"off": 0, "always": 1, "fullscreen": 2}[prefs["vrr"]]
    return values


def option(name):
    value = json.loads(run("hyprctl", "-j", "getoption", name))
    for kind in ("bool", "int", "float", "css"):
        if kind in value:
            return value[kind]
    raise ValueError(f"Cannot read Hyprland option {name}")


def lua(value):
    if isinstance(value, dict):
        return "{" + ",".join(f"[{json.dumps(key)}]={lua(item)}" for key, item in value.items()) + "}"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)) and math.isfinite(value):
        return str(value)
    raise ValueError("Invalid Hyprland value")


def apply(values):
    tree = {}
    for name, value in values.items():
        if name not in targets(DEFAULTS | dict(allowTearing=True, hideBorders=True, vrr="always")):
            raise ValueError(f"Unexpected saved option: {name}")
        node = tree
        *parents, key = name.split(":")
        for parent in parents:
            node = node.setdefault(parent, {})
        if name in ("general:gaps_in", "general:gaps_out"):
            parts = str(value).split()
            if len(parts) != 4:
                raise ValueError("Invalid saved window gaps")
            value = dict(zip(("top", "right", "bottom", "left"), map(int, parts)))
        node[key] = value
    if tree:
        run("hyprctl", "eval", f"hl.config({lua(tree)})")


def window_rule(prefs=None):
    # Keep the handle: disabling it restores every application's existing rules.
    code = ""
    for handle in ("caelestiaGameModeRule", "caelestiaGameModeTearingRule"):
        code += f"if _G.{handle} then pcall(function() _G.{handle}:set_enabled(false) end) end; _G.{handle}=nil; "
    effects = {}
    if prefs:
        if prefs["opaqueWindows"]:
            effects["opacity"] = "1 override"
            effects["force_rgbx"] = True
            effects["opaque"] = True
        if prefs["squareCorners"]:
            effects["rounding"] = 0
        if prefs["hideBorders"]:
            effects["border_size"] = 0
    if effects:
        spec = dict(name="caelestia-game-mode", match={"class": ".*"}) | effects
        code += f"_G.caelestiaGameModeRule=hl.window_rule({lua(spec)}); assert(_G.caelestiaGameModeRule:is_enabled()); "
    if prefs and prefs["allowTearing"]:
        code += '_G.caelestiaGameModeTearingRule=hl.window_rule({name="caelestia-game-mode-tearing", match={fullscreen=true}, immediate=true}); '
    run("hyprctl", "eval", "(function() " + code + "end)()")


def profile():
    value = run("tlpctl", "get")
    if value not in PROFILES:
        raise ValueError(f"Unrecognised power profile: {value}")
    return value


def set_profile(value):
    if value not in PROFILES:
        raise ValueError("Invalid saved power profile")
    run("tlpctl", "set", value)
    # tlp-pd acknowledges Set before publishing the new ActiveProfile.
    for _ in range(40):
        if profile() == value:
            return
        time.sleep(0.1)
    raise RuntimeError(f"Power profile did not switch to {value}")


def verify(values):
    mismatches = [name for name, expected in values.items() if option(name) != expected]
    if mismatches:
        raise RuntimeError("Hyprland settings differ: " + ", ".join(mismatches))


def hardware(action):
    data = json.loads(run("sudo", "-n", ULTRA_HELPER, action))
    if not data.get("ok"):
        raise RuntimeError(data.get("error", "Ultra hardware operation failed"))
    return data


def quota(unit):
    escaped = "".join(c if c.isascii() and c.isalnum() else f"_{ord(c):02x}" for c in unit)
    return json.loads(run("busctl", "--user", "--json=short", "get-property",
                          "org.freedesktop.systemd1", f"/org/freedesktop/systemd1/unit/{escaped}",
                          "org.freedesktop.systemd1.Service", "CPUQuotaPerSecUSec"))["data"]


def set_quota(unit, value):
    if unit not in BACKGROUND_UNITS:
        raise ValueError("Unexpected background service")
    percent = "" if value == 2**64 - 1 else f"{value / 10000:g}%"
    run("systemctl", "--user", "set-property", "--runtime", unit, f"CPUQuota={percent}")
    if quota(unit) != value:
        raise RuntimeError(f"CPU quota did not change for {unit}")


def capture_ultra():
    units = {}
    for unit in BACKGROUND_UNITS:
        if run("systemctl", "--user", "show", "--value", "-p", "LoadState", unit) == "loaded":
            units[unit] = quota(unit)
    bluetooth = subprocess.run(["busctl", "--system", "get-property", "org.bluez", "/org/bluez/hci0",
                                "org.bluez.Adapter1", "Powered"], capture_output=True, text=True, timeout=5)
    return dict(quotas=units, bluetoothWasOn=bluetooth.returncode == 0 and bluetooth.stdout.strip() == "b true",
                bluetoothChanged=False)


def enable_ultra(session):
    hardware("enable")
    for unit, previous in session["ultra"]["quotas"].items():
        set_quota(unit, min(previous, 250_000))  # 25% of one CPU; never raise an existing limit.
    if session["ultra"]["bluetoothWasOn"] and not run("bluetoothctl", "devices", "Connected"):
        session["ultra"]["bluetoothChanged"] = True
        write(STATE, session)
        run("bluetoothctl", "power", "off")


def restore_ultra(session):
    errors = []
    for operation in [lambda: hardware("disable")]:
        try:
            operation()
        except Exception as error:
            errors.append(str(error))
    for unit, previous in session["ultra"]["quotas"].items():
        try:
            if quota(unit) == min(previous, 250_000):
                set_quota(unit, previous)
        except Exception as error:
            errors.append(str(error))
    if session["ultra"].get("bluetoothChanged"):
        try:
            powered = run("busctl", "--system", "get-property", "org.bluez", "/org/bluez/hci0",
                          "org.bluez.Adapter1", "Powered")
            if powered == "b false":
                run("bluetoothctl", "power", "on")
        except Exception as error:
            errors.append(str(error))
    if errors:
        raise RuntimeError("; ".join(errors))


def restore(session):
    errors = []
    if session.get("mode") == "ultra":
        try:
            restore_ultra(session)
        except Exception as error:
            errors.append(str(error))
    if session["signature"] == os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""):
        try:
            window_rule()
            apply(session["previousOptions"])
            verify(session["previousOptions"])
        except Exception as error:
            errors.append(str(error))
    if session.get("previousProfile"):
        try:
            if profile() == session["settings"]["powerProfile"]:
                set_profile(session["previousProfile"])
        except Exception as error:
            errors.append(str(error))
    if errors:
        raise RuntimeError("; ".join(errors))
    session["active"] = False
    write(STATE, session)


def execute(action, argument=None):
    prefs = settings(read(CONFIG, {}))
    profiles = game_profiles.load()
    selected = game_profiles.selected(profiles)
    if selected:
        prefs = settings(prefs | selected.get("mode", {}))
    session = read(STATE, {"active": False})
    if session["active"]:
        session["settings"] = settings(session["settings"])
    error = ""
    hardware_state = {}
    try:
        if session["active"] and session["signature"] != os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""):
            restore(session)
        if action == "configure":
            if session["active"]:
                raise ValueError("Disable Game Mode before changing its settings")
            changed = settings(prefs | json.loads(argument))
            if selected:
                selected["mode"] = changed
                game_profiles.save(profiles)
            else:
                write(CONFIG, changed)
            prefs = changed
        elif action == "defaults":
            if session["active"]:
                raise ValueError("Disable Game Mode before changing its settings")
            if selected:
                selected["mode"] = dict(DEFAULTS)
                game_profiles.save(profiles)
            else:
                write(CONFIG, DEFAULTS)
            prefs = dict(DEFAULTS)
        elif action in ("enable", "enable-ultra"):
            mode = "ultra" if action == "enable-ultra" else "game"
            if session["active"] and session.get("mode", "game") == mode:
                return execute("status")
            if mode == "game" and selected and game_profiles.frame_generation_active(selected.get("render", {}).get("frameGeneration", 1)) and prefs["allowTearing"]:
                raise ValueError("Disable screen tearing before enabling a frame-generation profile")
            if argument not in ("true", "false"):
                raise ValueError("Previous notification state is required")
            previous_dnd = session["previousDnd"] if session["active"] else argument == "true"
            if session["active"]:
                restore(session)
            active_prefs = ULTRA if mode == "ultra" else prefs
            desired = targets(active_prefs)
            session = dict(active=True, mode=mode, signature=os.environ["HYPRLAND_INSTANCE_SIGNATURE"],
                           settings=active_prefs, previousOptions={key: option(key) for key in desired},
                           previousProfile=profile() if active_prefs["powerProfile"] != "keep" else None,
                           previousDnd=previous_dnd)
            if mode == "ultra":
                session["ultra"] = capture_ultra()
            write(STATE, session)  # Journal precedes every mutation, including TLP.
            try:
                if active_prefs["powerProfile"] != "keep":
                    set_profile(active_prefs["powerProfile"])
                if mode == "ultra":
                    enable_ultra(session)
                apply(desired)
                window_rule(active_prefs)
                verify(desired)
            except Exception as failure:
                try:
                    restore(session)
                except Exception as rollback:
                    raise RuntimeError(f"{failure}; Restore failed: {rollback}") from failure
                raise
        elif action == "disable" and session["active"]:
            restore(session)
        elif action == "reapply" and session["active"]:
            if session["signature"] != os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""):
                restore(session)
            else:
                apply(targets(session["settings"]))
                window_rule(session["settings"])
                verify(targets(session["settings"]))
                if session.get("mode") == "ultra":
                    hardware("reapply")
        elif action in ("dim", "undim"):
            if session["active"] and session.get("mode") == "ultra":
                hardware(action)
        elif action not in ("status", "disable", "reapply"):
            raise ValueError("Unknown Game Mode command")
    except Exception as failure:
        error = str(failure)
        session = read(STATE, {"active": False})
    actual_profile = ""
    try:
        actual_profile = profile()
        if session["active"] and session["settings"]["powerProfile"] != "keep" and actual_profile != session["settings"]["powerProfile"]:
            raise RuntimeError("Selected power profile is no longer active")
    except Exception as failure:
        if session["active"] and session.get("previousProfile"):
            error = error or str(failure)
    if session["active"] and action == "status":
        try:
            verify(targets(session["settings"]))
        except Exception as failure:
            error = error or str(failure)
    if session["active"] and session.get("mode") == "ultra":
        try:
            hardware_state = hardware("status")
            if not hardware_state["active"]:
                raise RuntimeError("Ultra hardware controls are no longer active")
            if hardware_state["issues"]:
                raise RuntimeError("Ultra hardware settings changed: " + ", ".join(hardware_state["issues"]))
        except Exception as failure:
            error = error or str(failure)
    return dict(ok=not error, error=error, settings=prefs, session=session, actualProfile=actual_profile,
                hardware=hardware_state, profileName=selected["name"] if selected else "", selectedProfile=profiles.get("selected", ""))


def main():
    STATE.parent.mkdir(parents=True, exist_ok=True)
    with STATE.with_suffix(".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            result = execute(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
        except Exception as error:
            result = dict(ok=False, error=str(error))
        print(json.dumps(result))
        return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
