#!/usr/bin/env python3
"""Stream package-manager prompts into Nexus through a real PTY."""
import codecs
import errno
import fcntl
import json
import os
import pty
import re
import selectors
import struct
import sys
import termios


def commands_for(items):
    if not isinstance(items, list) or not items:
        raise ValueError("Select at least one update")
    groups = {source: [] for source in ("repo", "aur", "flatpak", "snap")}
    for item in items:
        if not isinstance(item, dict) or item.get("source") not in groups or not isinstance(item.get("id"), str) or not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9@._+:/-]*", item["id"]):
            raise ValueError("Invalid update selection")
        groups[item["source"]].append(item["id"])
    commands = []
    # Arch upgrades are atomic as a group; never generate a partial system upgrade.
    if groups["repo"] or groups["aur"]:
        commands.append(["paru", "-Syu"])
    if groups["flatpak"]:
        commands.append(["flatpak", "update", "--", *groups["flatpak"]])
    if groups["snap"]:
        commands.append(["sudo", "snap", "refresh", "--", *groups["snap"]])
    return commands


def emit(event):
    try:
        print(json.dumps(event), flush=True)
    except BrokenPipeError:
        # The systemd service finishes an active transaction if the shell closes.
        sys.stdout = open(os.devnull, "w")


def run_command(command):
    pid, master = pty.fork()
    if pid == 0:
        os.environ.update(TERM="dumb", NO_COLOR="1", PAGER="cat", PARU_PAGER="cat", EDITOR="cat", VISUAL="cat")
        try:
            os.execvp(command[0], command)
        except OSError as error:
            print(error, file=sys.stderr, flush=True)
            os._exit(127)
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    selector = selectors.DefaultSelector()
    selector.register(master, selectors.EVENT_READ)
    selector.register(sys.stdin, selectors.EVENT_READ)
    decoder = codecs.getincrementaldecoder("utf-8")("replace")
    incoming = b""
    last_echo = None
    output = ""
    connected = True
    try:
        while True:
            echo = bool(termios.tcgetattr(master)[3] & termios.ECHO)
            if echo != last_echo or output:
                emit({"output": output, "echo": echo})
                output, last_echo = "", echo
            events = selector.select(0.05)
            finished = False
            for key, _ in events:
                if key.fileobj == master:
                    try:
                        data = os.read(master, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        data = b""
                    if not data:
                        finished = True
                        break
                    output += decoder.decode(data)
                else:
                    data = os.read(sys.stdin.fileno(), 65536)
                    if not data:
                        selector.unregister(sys.stdin)
                        connected = False
                        continue
                    incoming += data
                    while b"\n" in incoming:
                        line, incoming = incoming.split(b"\n", 1)
                        try:
                            response = json.loads(line)
                            if not isinstance(response, str) or len(response) > 8192:
                                raise ValueError("Invalid response")
                            os.write(master, response.encode() + b"\n")
                        except (ValueError, UnicodeError):
                            emit({"output": "\nInvalid package response\n", "echo": echo})
            if finished:
                emit({"output": output + decoder.decode(b"", final=True), "echo": True})
                _, status = os.waitpid(pid, 0)
                return os.waitstatus_to_exitcode(status), connected
    finally:
        selector.close()
        os.close(master)


def main(args):
    if args[0] == "plan":
        print(json.dumps(commands_for(json.loads(args[1]))))
        return 0
    if args[0] == "self-check":
        # Exercise hidden input without running a package manager.
        commands = [[sys.executable, "-c", "import getpass; value=getpass.getpass('Test password: '); print('accepted' if value == 'test-secret' else 'rejected'); raise SystemExit(0 if value == 'test-secret' else 1)"]]
    elif args[0] == "run":
        commands = commands_for(json.loads(args[1]))
    else:
        raise ValueError("Unknown update action")
    for command in commands:
        emit({"output": "\n$ " + " ".join(command[:2]) + "\n", "echo": True})
        code, connected = run_command(command)
        if code or not connected:
            emit({"done": True, "code": code or 1})
            return code or 1
    emit({"done": True, "code": 0})
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError, IndexError) as error:
        emit({"output": str(error) + "\n", "done": True, "code": 1})
        sys.exit(1)
