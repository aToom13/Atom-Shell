#!/usr/bin/env python3
"""Desktop-independent default application associations."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from autostart import installed_app, run

GROUPS = {
    "Web browser": ["x-scheme-handler/http", "x-scheme-handler/https", "text/html"],
    "Email": ["x-scheme-handler/mailto"],
    "File manager": ["inode/directory"],
    "PDF documents": ["application/pdf"],
    "Text files": ["text/plain"],
    "Images": ["image/png", "image/jpeg", "image/webp", "image/gif"],
    "Videos": ["video/mp4", "video/webm", "video/x-matroska"],
    "Audio": ["audio/mpeg", "audio/ogg", "audio/flac"],
}


def mime_types(key):
    if key in GROUPS:
        return GROUPS[key]
    if not re.fullmatch(r"[a-zA-Z0-9!#$&^_.+-]+/[a-zA-Z0-9!#$&^_.+-]+", key):
        raise ValueError("Enter a valid file type, such as application/pdf")
    return [key]


def query(key):
    current = [run("xdg-mime", "query", "default", mime).strip() for mime in mime_types(key)]
    return dict(key=key, current=current[0], mixed=len(set(current)) > 1)


def main(args):
    action, *values = args
    if action == "list":
        print(json.dumps([query(key) for key in GROUPS]))
    elif action == "query" and len(values) == 1:
        print(json.dumps(query(values[0])))
    elif action == "set" and len(values) == 2:
        key, identifier = values
        types = mime_types(key)
        installed_app(identifier)
        Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")).mkdir(parents=True, exist_ok=True)
        run("xdg-mime", "default", identifier, *types)
        if any(run("xdg-mime", "query", "default", mime).strip() != identifier for mime in types):
            raise ValueError("The system did not accept the new default application")
    else:
        raise ValueError("Unknown default application action")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, IndexError, subprocess.SubprocessError) as error:
        print(getattr(error, "stderr", None) or str(error), file=sys.stderr)
        sys.exit(1)
