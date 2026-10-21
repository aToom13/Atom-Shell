#!/usr/bin/env python3
"""Manage personal XDG autostart entries; systemd handles their execution."""
import configparser
import io
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import uuid

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
DIRECTORY = CONFIG / "autostart"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=30).stdout


def entry_path(identifier):
    if not identifier or Path(identifier).name != identifier or not identifier.endswith(".desktop") or "\x00" in identifier:
        raise ValueError("Invalid startup entry")
    return DIRECTORY / identifier


def read(path):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    with path.open(encoding="utf-8") as stream:
        parser.read_file(stream)
    if "Desktop Entry" not in parser:
        raise ValueError(f"Invalid desktop entry: {path.name}")
    return parser


def write(path, parser):
    section = parser["Desktop Entry"]
    if section.get("Terminal", "false").lower() == "true":
        # systemd's desktop generator does not implement Terminal=true.
        if not shutil.which("kitty"):
            raise ValueError("Kitty is required for terminal startup commands")
        section["X-AtomShell-Command"] = section["Exec"]
        section["X-AtomShell-Terminal"] = "true"
        section["Exec"] = "/usr/bin/kitty -e " + section["Exec"]
        section["Terminal"] = "false"
    DIRECTORY.mkdir(parents=True, exist_ok=True)
    text = io.StringIO()
    parser.write(text, space_around_delimiters=False)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=DIRECTORY, suffix=".desktop", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(text.getvalue())
            stream.flush()
            os.fsync(stream.fileno())
        run("desktop-file-validate", str(temporary))
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def entries():
    items = []
    # ponytail: personal entries only; system-wide startup stays with the desktop.
    for path in sorted(DIRECTORY.glob("*.desktop")):
        try:
            section = read(path)["Desktop Entry"]
            items.append(dict(id=path.name, name=section.get("Name", path.stem),
                              command=section.get("X-AtomShell-Command", section.get("Exec", "")),
                              directory=section.get("Path", ""),
                              terminal=section.get("X-AtomShell-Terminal", section.get("Terminal", "false")).lower() == "true",
                              enabled=section.get("Hidden", "false").lower() != "true"
                              and section.get("X-GNOME-Autostart-enabled", "true").lower() != "false"))
        except (OSError, ValueError, configparser.Error) as error:
            raise ValueError(f"Cannot read {path.name}: {error}") from error
    return sorted(items, key=lambda item: item["name"].casefold())


def unit(identifier):
    return "app-" + run("systemd-escape", identifier.removesuffix(".desktop")).strip() + "@autostart.service"


def save(identifier, name, command, options_json=None):
    name, command = name.strip(), command.strip()
    if not name or not command or any(char in name + command for char in "\r\n\x00"):
        raise ValueError("Enter a name and a single-line command")
    executable = shlex.split(command)[0]
    if not shutil.which(executable):
        raise ValueError(f"Program not found: {executable}")
    options = json.loads(options_json) if options_json is not None else None
    if options is not None:
        if not isinstance(options, dict) or set(options) != {"directory", "terminal", "enabled"} or not isinstance(options["directory"], str) or any(type(options[key]) is not bool for key in ("terminal", "enabled")):
            raise ValueError("Invalid startup options")
        directory = options["directory"].strip()
        if directory and (any(c in directory for c in "\r\n\x00") or not Path(directory).expanduser().is_dir()):
            raise ValueError("Working folder does not exist")
    path = entry_path(identifier or f"atomshell-{uuid.uuid4().hex}.desktop")
    parser = read(path) if identifier else configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    if "Desktop Entry" not in parser:
        parser["Desktop Entry"] = {"Type": "Application", "Terminal": "false"}
    section = parser["Desktop Entry"]
    if section.pop("X-AtomShell-Terminal", "false") == "true":
        section["Terminal"] = "true"
    section.pop("X-AtomShell-Command", None)
    for key in list(section):
        if key.startswith("Name["):
            del section[key]
    section["Name"], section["Exec"] = name, command
    if options is not None:
        section["Path"] = str(Path(directory).expanduser().resolve()) if directory else ""
        section["Terminal"] = str(options["terminal"]).lower()
        section["Hidden"] = str(not options["enabled"]).lower()
        section.pop("X-GNOME-Autostart-enabled", None)
    write(path, parser)


def installed_app(identifier):
    entry_path(identifier)
    data_dirs = [Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))]
    data_dirs += [Path(p) for p in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if p]
    for base in data_dirs:
        applications = base / "applications"
        for path in applications.rglob("*.desktop"):
            if str(path.relative_to(applications)).replace("/", "-") != identifier:
                continue
            parser = read(path)
            section = parser["Desktop Entry"]
            if section.get("Type") != "Application" or not section.get("Exec"):
                raise ValueError("This application has no startup command")
            return parser
    raise ValueError("Installed application not found")


def add_app(identifier):
    parser = installed_app(identifier)
    for key in ("Hidden", "OnlyShowIn", "NotShowIn", "X-GNOME-Autostart-enabled", "DBusActivatable"):
        parser["Desktop Entry"].pop(key, None)
    write(entry_path(identifier), parser)


def main(args):
    action, *values = args
    if action == "list":
        print(json.dumps(entries()))
        return
    if action == "session":
        run("systemctl", "--user", "daemon-reload")
        units = [unit(item["id"]) for item in entries() if item["enabled"]]
        if units:
            run("systemctl", "--user", "start", "--no-block", *units)
        return
    if action == "save" and len(values) in (3, 4):
        save(*values)
    elif action == "add-app" and len(values) == 1:
        if entry_path(values[0]).exists():
            raise ValueError("This application is already in the startup list")
        add_app(values[0])
    elif action == "toggle" and len(values) == 2 and values[1] in ("true", "false"):
        path = entry_path(values[0])
        parser = read(path)
        parser["Desktop Entry"]["Hidden"] = "false" if values[1] == "true" else "true"
        parser["Desktop Entry"].pop("X-GNOME-Autostart-enabled", None)
        write(path, parser)
    elif action == "delete" and len(values) == 1:
        entry_path(values[0]).unlink()
    else:
        raise ValueError("Unknown startup action")
    run("systemctl", "--user", "daemon-reload")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, IndexError, configparser.Error, subprocess.SubprocessError) as error:
        print((getattr(error, "stderr", None) or getattr(error, "stdout", None) or str(error)).strip(), file=sys.stderr)
        sys.exit(1)
