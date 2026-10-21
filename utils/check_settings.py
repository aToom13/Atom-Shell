#!/usr/bin/env python3
"""Isolated native-settings checks; never installs or updates packages."""
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch
import default_apps
import region
import update_session

assert update_session.commands_for([{"source": "aur", "id": "example-git"}]) == [["paru", "-Syu"]]
assert update_session.commands_for([{"source": "flatpak", "id": "org.example.App"}]) == [["flatpak", "update", "--", "org.example.App"]]
for item in ({"source": "repo", "id": "--overwrite"}, {"source": "repo", "id": "x;touch /tmp/pwned"}, {"source": "invalid", "id": "x"}):
    try:
        update_session.commands_for([item])
    except ValueError:
        pass
    else:
        raise AssertionError("Invalid update selection accepted")

with tempfile.TemporaryDirectory(prefix="nexus-settings-check-") as temporary:
    base = Path(temporary)
    keyboard = base / "keyboard.lua"
    keyboard.write_text(region.keyboard_text("tr,us", "f,"))
    subprocess.run(["luac", "-p", str(keyboard)], check=True)
    for layout, variant in [("tr\"});os.execute('false')", ""), ("tr", "not-a-variant"), ("tr,us,de,fr,gb", "")]:
        try:
            region.keyboard_text(layout, variant)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid keyboard configuration accepted")
    applications = base / "data/applications"
    applications.mkdir(parents=True)
    (applications / "sample.desktop").write_text("[Desktop Entry]\nType=Application\nName=Sample\nExec=/usr/bin/true\n")
    with patch.dict(os.environ, {"HOME": str(base), "XDG_CONFIG_HOME": str(base / "config"), "XDG_DATA_HOME": str(base / "data"), "XDG_DATA_DIRS": str(base / "empty"), "XDG_CURRENT_DESKTOP": "Hyprland", "DE": "generic"}):
        default_apps.main(["set", "Web browser", "sample.desktop"])
        assert default_apps.query("Web browser") == {"key": "Web browser", "current": "sample.desktop", "mixed": False}
        try:
            default_apps.main(["set", "application/pdf", "../escape.desktop"])
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid desktop entry accepted")

helper = Path(__file__).with_name("update_session.py")
process = subprocess.Popen(["systemd-run", "--user", "--collect", "--wait", "--pipe", "--unit=atomshell-updates-check", sys.executable, str(helper), "self-check"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
deadline = time.monotonic() + 15
events, sent = [], False
try:
    while time.monotonic() < deadline:
        if not selector.select(0.2):
            continue
        line = process.stdout.readline()
        if not line:
            break
        event = json.loads(line)
        events.append(event)
        if event.get("echo") is False and not sent:
            process.stdin.write(json.dumps("test-secret") + "\n")
            process.stdin.flush()
            sent = True
        if event.get("done"):
            break
    assert process.wait(timeout=5) == 0, process.stderr.read()
    output = "".join(event.get("output", "") for event in events)
    assert sent and "accepted" in output and "test-secret" not in output
    assert events[-1].get("done") and events[-1]["code"] == 0
finally:
    selector.close()
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=5)

print("PASS: MIME associations, input validation, Hyprland layout, update plans, systemd PTY, hidden password input")

if "--ui" in sys.argv:
    shell = Path(__file__).resolve().parent.parent
    qml = '''import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.services
import qs.modules.nexus as Nexus
ShellRoot {
    id: root
    property int step: 0
    property bool bottomShot: false
    property var pages: ["apps/AutostartPage.qml", "apps/DefaultAppsPage.qml", "LanguageAndRegion.qml", "UpdatesPage.qml"]
    Nexus.NexusState { id: state; screen: Quickshell.screens[0]; isWindow: true }
    PanelWindow {
        id: window
        visible: true
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        implicitWidth: 1100
        implicitHeight: 1000
        color: Colours.palette.m3surface
        contentItem.Config.screen: screen.name
        contentItem.Tokens.screen: screen.name
        Loader {
            id: page
            anchors.fill: parent
            anchors.margins: 24
        }
    }
    function next() {
        if (step === pages.length) { console.log("SETTINGS_UI_PASS"); Qt.quit(); return; }
        page.setSource("modules/nexus/pages/" + pages[step], { nState: state });
        settle.restart();
    }
    Timer {
        id: settle
        interval: 1600
        onTriggered: {
            if (!page.item) { console.error("SETTINGS_UI_FAIL: page missing"); Qt.quit(); return; }
            if (root.step === 0) page.item.showPicker = true;
            if (root.step === 1) page.item.selectedKey = "PDF documents";
            if (root.step === 3) { UpdateRunner.output = "Package transaction details appear here.\\nNo real updates started."; UpdateRunner.result = 0; }
            capture.restart();
        }
    }
    Timer {
        id: capture
        interval: 250
        onTriggered: {
            page.grabToImage(result => {
                result.saveToFile("/tmp/caelestia-settings-check-" + root.step + (root.bottomShot ? "-bottom" : "") + ".png");
                if (!root.bottomShot) {
                    root.bottomShot = true;
                    page.item.flickable.contentY = Math.max(0, page.item.flickable.contentHeight + page.item.flickable.bottomMargin - page.item.flickable.height);
                    capture.restart();
                    return;
                }
                console.log("SETTINGS_UI_PAGE " + root.pages[root.step]);
                root.bottomShot = false;
                root.step++;
                root.next();
            });
        }
    }
    Component.onCompleted: next()
}'''
    handle, filename = tempfile.mkstemp(prefix="SettingsCheck", suffix=".qml", dir=shell)
    try:
        with os.fdopen(handle, "w") as stream:
            stream.write(qml)
        environment = dict(os.environ, QT_QPA_PLATFORM="wayland")
        try:
            result = subprocess.run(["qs", "--no-color", "-p", filename], capture_output=True, text=True, env=environment, timeout=20)
        except subprocess.TimeoutExpired as error:
            print((error.stdout or b"").decode(errors="replace") + (error.stderr or b"").decode(errors="replace"))
            raise
        output = result.stdout + result.stderr
        print(output)
        assert result.returncode == 0 and "SETTINGS_UI_PASS" in output
        assert not any(error in output for error in ("SETTINGS_UI_FAIL", "TypeError", "ReferenceError", "Unable to assign", "Cannot assign", "is not a type"))
    finally:
        Path(filename).unlink(missing_ok=True)
