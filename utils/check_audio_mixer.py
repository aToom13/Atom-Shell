#!/usr/bin/env python3
"""Run against the loaded shell: python3 ~/.config/quickshell/caelestia/utils/check_audio_mixer.py.

Creates silent playback streams; exercises real keyboard input. Never changes
the system output or system volume. Removes its streams and closes the panel.
"""
import json
import os
import subprocess
import time


def audio(method, *args):
    return subprocess.check_output(
        ["qs", "-c", "caelestia", "ipc", "call", "audio", method, *args], text=True
    ).strip()


def status():
    return json.loads(audio("mixerStatus"))


def wait_for(predicate, message, timeout=6):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = status()
        if predicate(value):
            return value
        time.sleep(0.06)
    raise AssertionError(f"{message}: {status()}")


def key(*keys):
    codes = {"Tab": 15, "Right": 106, "Left": 105, "Up": 103, "Down": 108, "Return": 28, "Escape": 1, "m": 50, "XF86AudioRaiseVolume": 115}
    events = [f"{codes[k]}:{pressed}" for k in keys for pressed in (1, 0)]
    subprocess.run(["ydotool", "key", "--key-delay=20", *events], check=True)
    time.sleep(0.10)


def entry(state, app):
    return next((e for e in state.get("entries", []) if e.get("key") == app), {"nodes": []})


def pulse(kind):
    return json.loads(subprocess.check_output(["pactl", "-f", "json", "list", kind], text=True))


def stop(process):
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=3)


def main():
    processes = []
    pid = os.getpid()
    app_a, app_b = f"caelestia.mixer.check.a.{pid}", f"caelestia.mixer.check.b.{pid}"
    try:
        for app, name in [(app_a, "Mixer Check A"), (app_a, "Mixer Check A"), (app_b, "Mixer Check B")]:
            processes.append(subprocess.Popen([
                "pw-play", "--raw", "--rate", "8000", "--channels", "1", "--format", "s16", "--volume", "0.35",
                "-P", json.dumps({"application.name": name, "application.id": app}), "/dev/zero"
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))

        audio("closeMixer")
        audio("showOsd")
        wait_for(lambda s: s["armed"], "Tab not armed")
        time.sleep(0.15)
        key("Tab")
        start = wait_for(lambda s: s.get("focused") and len(s.get("entries", [])) >= 3, "Tab did not open mixer")
        assert len(entry(start, app_a)["nodes"]) == 2, "Application streams not grouped"
        assert len(entry(start, app_b)["nodes"]) == 1
        assert start["width"] > 180, "Panel did not grow for apps"

        expected = {n["name"] for n in pulse("sinks") if not any(
            p["name"] == n.get("active_port") and p["availability"] == "not available" for p in n.get("ports", []))}
        all_sinks = pulse("sinks")
        shown = {n["id"] for n in start["devices"]}
        dumped = json.loads(subprocess.check_output(["pw-dump"], text=True))
        shown_names = {n.get("info", {}).get("props", {}).get("node.name") for n in dumped if n["id"] in shown}
        assert shown_names == expected, f"Unavailable output filtering failed: {shown_names} != {expected}"

        # Left/right selects an app; Enter edits; arrows and media keys edit it.
        for _ in range(len(start["entries"])):
            if status()["selected"] == app_a:
                break
            key("Right")
        state = wait_for(lambda s: s.get("selected") == app_a, "App not selected")
        before_a = [n["volume"] for n in entry(state, app_a)["nodes"]]
        before_b = entry(state, app_b)["nodes"][0]["volume"]
        key("Return")
        wait_for(lambda s: s.get("editing"), "Enter did not start editing")
        key("Up")
        state = wait_for(lambda s: bool(entry(s, app_a)["nodes"]) and all(n["volume"] > v + .01 for n, v in zip(entry(s, app_a)["nodes"], before_a)), "Grouped volume did not rise")
        assert entry(state, app_b)["nodes"] and abs(entry(state, app_b)["nodes"][0]["volume"] - before_b) < .002, "Other app volume changed"
        before_media = entry(state, app_a)["nodes"][0]["volume"]
        time.sleep(.2)
        key("XF86AudioRaiseVolume")
        wait_for(lambda s: entry(s, app_a)["nodes"][0]["volume"] > before_media + .01, "Media key did not target selected app")
        key("m")
        wait_for(lambda s: all(n["muted"] for n in entry(s, app_a)["nodes"]), "App mute failed")
        key("m", "Return", "Down", "Return")
        state = wait_for(lambda s: s.get("choosingDevice"), "App output picker did not open")

        # Route A to another usable output, keeping B and the system unchanged.
        if len(state["devices"]) > 1:
            target = next(n for n in state["devices"] if n["id"] != state["currentDevice"])
            default = state["defaultDevice"]
            other_output = entry(state, app_b)["output"]
            for _ in state["devices"]:
                if status()["pendingDevice"] == target["id"]:
                    break
                key("Down")
            key("Return")
            state = wait_for(lambda s: entry(s, app_a)["output"] == target["id"] and not s["routingBusy"], "App routing failed")
            assert state["defaultDevice"] == default, "System default changed during app routing"
            assert entry(state, app_b)["output"] == other_output, "Other app output changed"
            target_name = next(n["info"]["props"]["node.name"] for n in dumped if n["id"] == target["id"])
            pulse_target = next(n["index"] for n in all_sinks if n["name"] == target_name)
            routed = [n for n in pulse("sink-inputs") if n["properties"].get("application.id") == app_a]
            assert len(routed) == 2 and all(n["sink"] == pulse_target for n in routed), "Not all grouped streams routed"
        else:
            key("Escape")

        # Removing the selected app must not leave stale objects or selection.
        for process in processes[:2]:
            stop(process)
        wait_for(lambda s: s.get("selected") == "system" and len(s.get("entries", [])) == 2, "Removed app selection not reset")
        stop(processes[2])
        wait_for(lambda s: len(s.get("entries", [])) == 1 and s["width"] == 180, "Panel did not shrink")
        key("Escape")
        wait_for(lambda s: not s["open"] and not s["armed"], "Escape did not close mixer")
        print("PASS: Tab, arrows, Enter, media keys, grouped app volume, mute, output filtering, per-app routing, removal, adaptive width, Escape")
    finally:
        for process in processes:
            stop(process)
        audio("closeMixer")


if __name__ == "__main__":
    main()
