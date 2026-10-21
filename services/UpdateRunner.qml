pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property bool running: worker.running
    property bool secretInput
    property string output
    property int result: -1

    function start(items: var): void {
        if (running) return;
        output = "";
        result = -1;
        secretInput = false;
        worker.command = ["systemd-run", "--user", "--collect", "--wait", "--pipe", "--unit=atomshell-updates",
            "python3", Qt.resolvedUrl("../utils/update_session.py").toString().replace("file://", ""), "run", JSON.stringify(items)];
        worker.running = true;
    }

    function respond(text: string): void {
        if (running) worker.write(JSON.stringify(text) + "\n");
    }

    function append(text: string): void {
        output = (output + text.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").replace(/\r/g, "\n")).slice(-80000);
    }

    Process {
        id: worker
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const event = JSON.parse(line);
                    if (event.echo !== undefined) root.secretInput = !event.echo;
                    if (event.output) root.append(event.output);
                    if (event.done) root.result = event.code;
                } catch (error) { root.append(line + "\n"); }
            }
        }
        stderr: SplitParser { onRead: line => root.append(line + "\n") }
        onExited: code => {
            if (root.result < 0) root.result = code;
            root.secretInput = false;
        }
    }
}
