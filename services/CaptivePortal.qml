pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool checking: false
    property bool portalDetected: false
    property string loginUrl: ""
    readonly property bool available: portalDetected && loginUrl.length > 0
    readonly property string probeUrl: "http://network-test.debian.org/nm"

    function check(): void {
        if (checking || connectivityProc.running || probeProc.running)
            return;

        if (!Nmcli.active) {
            clear();
            return;
        }

        checking = true;
        connectivityProc.command = ["nmcli", "networking", "connectivity"];
        connectivityProc.running = true;
    }

    function openLogin(): void {
        if (available)
            Quickshell.execDetached(["xdg-open", loginUrl]);
    }

    function clear(): void {
        portalDetected = false;
        loginUrl = "";
    }

    function resolveRedirect(location: string): string {
        const value = location.trim();
        if (!value)
            return "";
        if (/^https?:\/\//i.test(value))
            return value;

        try {
            return new URL(value, probeUrl).toString();
        } catch (error) {
            return "";
        }
    }

    property Process connectivityProc: Process {
        command: []

        stdout: StdioCollector {
            onStreamFinished: {
                const state = text.trim().toLowerCase();
                if (state === "full" || state === "unknown") {
                    root.clear();
                    root.checking = false;
                    return;
                }

                probeProc.command = ["curl", "--silent", "--show-error", "--include", "--max-time", "6", root.probeUrl];
                probeProc.running = true;
            }
        }

        stderr: SplitParser {
            onRead: { // qmllint disable signal-handler-parameters
                root.clear();
                root.checking = false;
            }
        }
    }

    property Process probeProc: Process {
        command: []

        stdout: StdioCollector {
            onStreamFinished: {
                const status = text.match(/^HTTP\/[\d.]+\s+(\d{3})/im);
                const redirect = text.match(/^Location:\s*(.+)$/im);
                const statusCode = status ? Number(status[1]) : 0;
                const resolved = redirect ? root.resolveRedirect(redirect[1]) : "";

                if (resolved && (statusCode < 200 || statusCode >= 300)) {
                    loginUrl = resolved;
                    portalDetected = true;
                } else if (statusCode === 200 && !text.includes("NetworkManager is online")) {
                    loginUrl = probeUrl;
                    portalDetected = true;
                } else {
                    clear();
                }

                checking = false;
            }
        }

        stderr: SplitParser {
            onRead: { // qmllint disable signal-handler-parameters
                clear();
                checking = false;
            }
        }
    }

    Component.onCompleted: check()

    Connections {
        target: Nmcli
        function onConnectivityChanged(): void { root.check(); }
        function onActiveChanged(): void { root.check(); }
    }
}
