pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var controller: null
    readonly property bool running: controller?.recording ?? props.running
    readonly property bool paused: controller?.paused ?? props.paused
    readonly property real elapsed: controller?.elapsed ?? props.elapsed
    property bool needsStart
    property list<string> startArgs
    property bool needsStop
    property bool needsPause

    function start(extraArgs = []): void {
        if (controller) {
            Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "picker", "openVideo"]);
            return;
        }
        needsStart = true;
        startArgs = extraArgs;
        checkProc.running = true;
    }

    function stop(): void {
        if (controller?.recording) { controller.stop(); return; }
        needsStop = true;
        checkProc.running = true;
    }

    function togglePause(): void {
        if (controller?.recording) { controller.togglePause(); return; }
        needsPause = true;
        checkProc.running = true;
    }

    PersistentProperties {
        id: props

        property bool running: false
        property bool paused: false
        property real elapsed: 0 // Might get too large for int

        reloadableId: "recorder"
    }

    Process {
        id: checkProc

        running: true
        command: ["pidof", "gpu-screen-recorder"]
        onExited: code => { // qmllint disable signal-handler-parameters
            props.running = code === 0;

            if (code === 0) {
                if (root.needsStop) {
                    Quickshell.execDetached(["caelestia", "record"]);
                    props.running = false;
                    props.paused = false;
                } else if (root.needsPause) {
                    Quickshell.execDetached(["caelestia", "record", "-p"]);
                    props.paused = !props.paused;
                }
            } else if (root.needsStart) {
                Quickshell.execDetached(["caelestia", "record", ...root.startArgs]);
                props.running = true;
                props.paused = false;
                props.elapsed = 0;
            }

            root.needsStart = false;
            root.needsStop = false;
            root.needsPause = false;
        }
    }

    Connections {
        // enabled: props.running && !props.paused
        function onSecondsChanged(): void {
            props.elapsed++;
        }

        target: Time // qmllint disable incompatible-type
    }
}
