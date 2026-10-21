#!/usr/bin/env python3
"""Run with python3 check_autostart.py; never changes the real startup list."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("autostart", Path(__file__).with_name("autostart.py"))
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


with tempfile.TemporaryDirectory(prefix="autostart-check-") as temporary:
    base = Path(temporary)
    startup.DIRECTORY = base / "config/autostart"
    calls = []
    real_run = startup.run

    def run(*args):
        if args[0] == "systemctl":
            calls.append(args)
            return ""
        return real_run(*args)

    environment = {"XDG_CONFIG_HOME": str(base / "config"), "XDG_CONFIG_DIRS": str(base / "empty"),
                   "XDG_DATA_HOME": str(base / "data"), "XDG_DATA_DIRS": str(base / "empty"),
                   "XDG_CURRENT_DESKTOP": "Hyprland"}
    with patch.dict(os.environ, environment), patch.object(startup, "run", run):
        startup.main(["save", "", "A test", '/usr/bin/printf "%%s" "hello world"'])
        item, = startup.entries()
        identifier = item["id"]
        assert item["enabled"] and item["name"] == "A test"
        original = startup.entry_path(identifier).read_bytes()
        for name, command in [("Bad\nExec=oops", "/usr/bin/true"), ("Missing", "missing-startup-executable"), ("Bad", '"')]:
            try:
                startup.main(["save", identifier, name, command])
            except ValueError:
                pass
            else:
                raise AssertionError("Invalid input accepted")
            assert startup.entry_path(identifier).read_bytes() == original
        for invalid in ("../escape.desktop", "/tmp/escape.desktop", "x", ""):
            try:
                startup.entry_path(invalid)
            except ValueError:
                pass
            else:
                raise AssertionError("Invalid path accepted")

        startup.main(["toggle", identifier, "false"])
        assert not startup.entries()[0]["enabled"]
        calls.clear()
        startup.main(["session"])
        assert not any("start" in call for call in calls)
        startup.main(["toggle", identifier, "true"])
        calls.clear()
        startup.main(["session"])
        assert calls[-1] == ("systemctl", "--user", "start", "--no-block", startup.unit(identifier))

        applications = base / "data/applications"
        applications.mkdir(parents=True)
        source = applications / "sample.desktop"
        source.write_text('[Desktop Entry]\nType=Application\nName=Sample\nName[tr]=Örnek\nExec=/usr/bin/printf "hello world"\nTerminal=true\nPath=/tmp\nOnlyShowIn=KDE;\nHidden=true\n')
        startup.main(["add-app", "sample.desktop"])
        parser = startup.read(startup.entry_path("sample.desktop"))
        assert parser["Desktop Entry"]["X-AtomShell-Terminal"] == "true"
        assert parser["Desktop Entry"]["Exec"].startswith("/usr/bin/kitty -e ")
        assert parser["Desktop Entry"]["Path"] == "/tmp"
        assert "OnlyShowIn" not in parser["Desktop Entry"]
        startup.main(["save", "sample.desktop", "Renamed", "/usr/bin/true"])
        assert "Name[tr]" not in startup.read(startup.entry_path("sample.desktop"))["Desktop Entry"]

        # Exercise the real systemd generator, including filename escaping and disabled entries.
        for directory in ("normal", "early", "late"):
            (base / directory).mkdir()
        subprocess.run(["/usr/lib/systemd/user-generators/systemd-xdg-autostart-generator",
                        str(base / "normal"), str(base / "early"), str(base / "late")], check=True, capture_output=True)
        generated = (base / "late" / startup.unit(identifier)).read_text()
        assert "ExecStart=" in generated and "printf" in generated
        assert (base / "late" / startup.unit("sample.desktop")).exists()

        options = json.dumps(dict(directory=str(base), terminal=True, enabled=False))
        startup.main(["save", identifier, "With options", "/usr/bin/true", options])
        item = next(item for item in startup.entries() if item["id"] == identifier)
        assert not item["enabled"] and item["terminal"] and item["directory"] == str(base)
        assert item["command"] == "/usr/bin/true"
        startup.main(["toggle", identifier, "true"])
        assert startup.read(startup.entry_path(identifier))["Desktop Entry"]["Exec"] == "/usr/bin/kitty -e /usr/bin/true"
        options = json.dumps(dict(directory="", terminal=False, enabled=True))
        startup.main(["save", identifier, "Plain", "/usr/bin/true", options])
        assert "X-AtomShell-Command" not in startup.read(startup.entry_path(identifier))["Desktop Entry"]

        startup.main(["delete", identifier])
        startup.main(["delete", "sample.desktop"])
        assert startup.entries() == [] and source.exists()
        assert not list(startup.DIRECTORY.glob("tmp*.desktop"))

print("PASS: CRUD, validation, atomic writes, app import, session dispatch, systemd generation")
