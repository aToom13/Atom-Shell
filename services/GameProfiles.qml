pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root
    property var windows: []
    property var profiles: []
    property var profile: null
    property var capabilities: ({})
    property string selected
    property string launchOptions
    property string error
    property var result
    property string action
    property bool testAfterSelect: false
    property string testSummary
    property int testMultiplier: 1
    readonly property bool testRunning: tester.running
    readonly property bool captureRunning: capturer.running
    property var captureInfo: null
    property var captureStats: null
    property real lastGameFps: 0
    property real lastGameFpsAt: 0
    property string lastGameFpsProfile
    property real captureBaselineFps: 0
    property real captureStartedAt: 0
    property int captureSlowSamples: 0
    property string captureWarning
    property bool captureStatsTimedOut: false
    property bool stoppingCapture: false
    property var sentCaptureSuspended: null
    readonly property bool captureSuspended: {
        const state = ShellState.forActive();
        return !!state && (state.utilities || state.dashboard || state.launcher || state.session || state.sidebar
            || state.osd || !!ShellState.componentsForActive()?.panels?.popouts?.hasCurrent);
    }
    readonly property bool busy: worker.running
    readonly property string helper: Qt.resolvedUrl("../utils/game_profiles.py").toString().replace("file://", "")

    function run(action, argument): void {
        if (busy)
            return;
        root.action = action;
        result = null;
        worker.exec(["/usr/bin/python3", helper, action, argument ?? ""]);
    }
    function configure(key: string, value: var): void {
        const change = {};
        change[key] = value;
        run("configure", JSON.stringify(change));
    }
    function select(key: string): void {
        if (!GameMode.busy && !GameMode.enabled && !captureRunning)
            run("select", key);
    }
    function startCapture(): void {
        if (!profile || busy || testRunning || captureRunning)
            return;
        error = "";
        captureBaselineFps = lastGameFpsProfile === selected && Date.now() - lastGameFpsAt < 20000 ? lastGameFps : 0;
        const refresh = Hypr.focusedMonitor?.lastIpcObject.refreshRate ?? 0;
        if (refresh > 0 && captureBaselineFps >= refresh * 0.95) {
            error = qsTr("Oyun zaten %1 FPS ile %2 Hz ekranı dolduruyor. Kare üretimi gerekmez.").arg(Math.round(captureBaselineFps)).arg(Math.round(refresh));
            return;
        }
        captureStartedAt = Date.now();
        captureSlowSamples = 0;
        captureWarning = "";
        captureStatsTimedOut = false;
        captureInfo = null;
        captureStats = null;
        sentCaptureSuspended = null;
        stoppingCapture = false;
        capturer.exec(["/usr/bin/python3", helper.replace("game_profiles.py", "game_capture.py"), selected]);
    }
    function stopCapture(): void {
        stoppingCapture = true;
        capturer.running = false;
    }
    function readCapture(line: string): void {
        const marker = "CAELESTIA_CAPTURE ";
        const offset = line.indexOf(marker);
        if (offset >= 0) {
            try {
                captureInfo = JSON.parse(line.slice(offset + marker.length));
                if (captureInfo.error) error = captureInfo.error;
            } catch (failure) { error = String(failure); }
        }
        const match = /([\d.]+) rendered fps, ([\d.]+) shown \((\d+)x\)/.exec(line);
        if (match) {
            captureStats = { rendered: Number(match[1]), shown: Number(match[2]), multiplier: Math.max(1, Math.round(Number(match[2]) / Number(match[1]))) };
            captureStatsTimedOut = false;
        }
        else if (line.includes("Caelestia live capture:"))
            error = line.trim();
    }
    function reportGameFps(fps: real): void {
        if (!Number.isFinite(fps) || fps < 0)
            return;
        if (!root.captureRunning) {
            root.lastGameFps = fps;
            root.lastGameFpsAt = Date.now();
            root.lastGameFpsProfile = root.selected;
            return;
        }
        if (!root.captureInfo?.active || !root.captureInfo?.ready || root.captureSuspended
            || root.captureBaselineFps <= 0 || Date.now() - root.captureStartedAt < 2000) {
            root.captureSlowSamples = 0;
            return;
        }
        root.captureSlowSamples = fps < root.captureBaselineFps * 0.85 ? root.captureSlowSamples + 1 : 0;
        if (root.captureSlowSamples >= 3) {
            root.captureWarning = qsTr("Kaynak %1, şimdi %2 FPS. Kare üretimi devrede.").arg(Math.round(root.captureBaselineFps)).arg(Math.round(fps));
            root.captureSlowSamples = 0;
        }
    }
    function testCube(): void {
        if (busy || testRunning || captureRunning)
            return;
        if (!profile) {
            testAfterSelect = true;
            select("test-cube");
        } else {
            error = "";
            testSummary = "";
            testMultiplier = profile.render.frameGeneration;
            tester.exec(["/usr/bin/python3", helper.replace("game_profiles.py", "game_launch.py"), selected, "--", "vkcube", "--wsi", "xcb", "--c", "150"]);
        }
    }
    Component.onCompleted: run("status")

    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.result = JSON.parse(text); }
                catch (error) { root.result = { ok: false, error: String(error) }; }
            }
        }
        stderr: StdioCollector {}
        onExited: exitCode => Qt.callLater(() => {
            const data = root.result;
            root.error = data?.ok ? "" : data?.error || qsTr("Could not load game profiles (exit %1)").arg(exitCode);
            if (!data?.ok) {
                root.testAfterSelect = false;
                return;
            }
            root.windows = data.windows;
            root.profiles = data.profiles;
            root.profile = data.profile;
            root.selected = data.selected;
            root.capabilities = data.capabilities;
            root.launchOptions = data.launchOptions;
            if (root.action === "select")
                GameMode.run("status");
            else if (root.action === "configure" && !GameMode.enabled && !GameMode.busy)
                GameMode.run("status");
            if (root.testAfterSelect) {
                root.testAfterSelect = false;
                root.testCube();
            }
            if (root.captureRunning && root.profile?.render.frameGeneration === 1)
                root.stopCapture();
        })
    }

    Process {
        id: capturer
        stdout: SplitParser {
            onRead: line => root.readCapture(line)
        }
        stderr: SplitParser {
            onRead: line => root.readCapture(line)
        }
        onExited: exitCode => {
            if (exitCode !== 0 && !root.stoppingCapture)
                root.error = root.error || qsTr("Pencere yakalama başarısız (kod %1).").arg(exitCode);
            root.captureInfo = null;
            root.captureStats = null;
            root.captureStatsTimedOut = false;
            root.stoppingCapture = false;
        }
    }
    Process { id: captureControl }
    Timer {
        interval: 12000
        running: root.captureRunning && !root.captureInfo?.ready
        onTriggered: {
            root.error = qsTr("Canlı yakalama başlatılamadı. Uygulamayı yeniden seçip tekrar deneyin.");
            root.stopCapture();
        }
    }
    Timer {
        interval: 6000
        running: root.captureRunning && !!root.captureInfo?.ready && root.captureInfo?.active && !root.captureStats
        onTriggered: root.captureStatsTimedOut = true
    }
    Timer {
        interval: 150
        repeat: true
        running: root.captureRunning
        onTriggered: {
            if (!root.captureInfo || captureControl.running || root.sentCaptureSuspended === root.captureSuspended)
                return;
            root.sentCaptureSuspended = root.captureSuspended;
            captureControl.exec(["qs", "-p", root.helper.replace("game_profiles.py", "capture/shell.qml"), "ipc", "call", "frameCapture", "suspend", String(root.captureSuspended)]);
        }
    }

    Process {
        id: tester
        environment: ({ KETTLE_FG_STATS: "true" })
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.includes("Caelestia game profile:"))
                    root.error = text.trim().slice(-700);
                const pattern = /([\d.]+) rendered fps, ([\d.]+) shown \((\d+)x\)/g;
                let current;
                let last = null;
                while ((current = pattern.exec(text)) !== null)
                    last = current;
                if (last) {
                    const ratio = Number(last[1]) > 0 ? Number(last[2]) / Number(last[1]) : 0;
                    root.testSummary = qsTr("Kaynak: %1 FPS · Gönderilen: %2 FPS · Ölçülen oran: %3×").arg(Math.round(Number(last[1]))).arg(Math.round(Number(last[2]))).arg(ratio.toFixed(1));
                } else if (root.testMultiplier > 1) {
                    root.error = qsTr("Bu testte kare üretimi doğrulanamadı.");
                }
            }
        }
        onExited: exitCode => Qt.callLater(() => {
            if (exitCode !== 0) {
                root.error = root.error || qsTr("3D test could not start (exit %1)").arg(exitCode);
                Toaster.toast(qsTr("3D test failed"), root.error, "error", Toast.Error);
            } else if (root.testMultiplier === 1) {
                root.testSummary = qsTr("3D test tamamlandı. Kare üretimi kapalı.");
            }
        })
    }

    IpcHandler {
        target: "gameProfiles"
        function refresh(): void { root.run("status"); }
        function testCube(): void { root.testCube(); }
        function startCapture(): void { root.startCapture(); }
        function stopCapture(): void { root.stopCapture(); }
        function select(key: string): void { root.select(key); }
        function configure(key: string, value: string): void { root.configure(key, JSON.parse(value)); }
        function status(): string {
            return JSON.stringify({ busy: root.busy, error: root.error, captureWarning: root.captureWarning, captureRunning: root.captureRunning, captureInfo: root.captureInfo, captureStats: root.captureStats, captureStatsTimedOut: root.captureStatsTimedOut, captureBaselineFps: root.captureBaselineFps, lastGameFps: root.lastGameFps, testRunning: root.testRunning, testSummary: root.testSummary, windows: root.windows, profiles: root.profiles, profile: root.profile, selected: root.selected, capabilities: root.capabilities, launchOptions: root.launchOptions });
        }
    }
}
