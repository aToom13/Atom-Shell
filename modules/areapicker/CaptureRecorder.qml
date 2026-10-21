pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Scope {
    id: root
    property bool recording: false
    property bool paused: false
    property bool pauseTarget: false
    property bool busy: false
    property real elapsed: 0
    property string error: ""
    property string saved: ""
    property var parts: []
    property var source: null
    property var context: ({})
    property bool sound: true
    property string phase: ""
    property var nextSource: null
    property bool nextPaused: false
    readonly property string helper: Qt.resolvedUrl("../../utils/capture_session.py").toString().replace("file://", "")

    function start(selection, audio): void {
        if (busy) return;
        if (recording) { changeSource(selection); return; }
        source = selection;
        context = selection.window ?? {};
        sound = audio;
        parts = [];
        elapsed = 0;
        error = saved = "";
        recording = true;
        openStream();
    }
    function openStream(): void {
        busy = true;
        paused = false;
        pauseTarget = false;
        phase = "starting";
        stream.exec(["/usr/bin/python3", helper, "stream", JSON.stringify(Object.assign({}, source, {sound: sound}))]);
    }
    function setPaused(value): void {
        if (!recording || busy || pauseTarget === value) return;
        pauseTarget = value;
        stream.write(value ? "pause\n" : "resume\n");
    }
    function togglePause(): void { setPaused(!paused); }
    function sameSource(selection): bool {
        if (!source || source.kind !== selection.kind) return false;
        if (source.kind === "window") return source.window.address === selection.window.address;
        return ["output", "x", "y", "width", "height"].every(key => source[key] === selection[key]);
    }
    function applySelection(selection, remainPaused = false): void {
        if (sameSource(selection)) setPaused(remainPaused);
        else changeSource(selection, remainPaused);
    }
    function changeSource(selection, remainPaused = false): void {
        if (!recording || busy) return;
        if (source.kind === "region" && selection.kind === "region" && source.output === selection.output) {
            stream.write(JSON.stringify(selection) + "\n");
            source = selection;
            setPaused(remainPaused);
            return;
        }
        nextSource = selection;
        nextPaused = remainPaused;
        phase = "switch";
        busy = true;
        stream.write("stop\n");
    }
    function stop(): void {
        if (!recording || busy) return;
        phase = "stop";
        busy = true;
        stream.write("stop\n");
    }
    function fail(message): void {
        error = message;
        phase = "stop";
        busy = true;
        if (stream.running) stream.write("stop\n");
        else complete();
    }
    function complete(): void {
        recording = paused = false;
        if (parts.length) {
            join.exec(["/usr/bin/python3", helper, "finish", JSON.stringify({ parts: parts, window: context })]);
        } else busy = false;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording && !root.paused && !root.busy
        onTriggered: root.elapsed++
    }
    Process {
        id: stream
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    if (data.error) { root.error = data.error; root.phase = "stop"; return; }
                    if (data.path) {
                        root.parts = [...root.parts, data.path];
                        root.busy = false;
                        root.paused = false;
                        root.phase = "";
                        if (root.nextPaused) { root.nextPaused = false; root.setPaused(true); }
                    }
                    if (data.paused !== undefined) root.paused = data.paused;
                } catch (failure) { root.fail(String(failure)); }
            }
        }
        onExited: code => {
            if (root.phase === "switch" && code === 0) {
                root.source = root.nextSource;
                root.openStream();
            } else if (root.phase === "stop") root.complete();
            else if (root.recording) root.fail(I18n.t("Capture stream ended (code %1). Recording parts preserved.", code));
        }
    }
    Process {
        id: join
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    if (data.error) root.error = data.error;
                    if (data.saved) root.saved = data.saved;
                } catch (failure) { root.error = String(failure); }
            }
        }
        onExited: code => {
            root.busy = false;
            if (code === 0 && root.saved) {
                root.parts = [];
                Quickshell.execDetached(["notify-send", "-a", "Atom Shell", I18n.t("Recording saved"), root.saved]);
            } else {
                if (!root.error) root.error = I18n.t("Failed to join recording. Parts preserved under ~/.local/state/caelestia/capture-parts.");
                Quickshell.execDetached(["notify-send", "-a", "Atom Shell", "-u", "critical", I18n.t("Failed to save recording"), root.error]);
            }
        }
    }
}
