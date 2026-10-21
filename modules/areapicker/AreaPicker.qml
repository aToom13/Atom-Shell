pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.containers
import qs.components.misc
import qs.services

Scope {
    id: scope
    CaptureRecorder { id: recorder }
    Component.onCompleted: Recorder.controller = recorder
    Component.onDestruction: Recorder.controller = null
    Process {
        id: keyLease
        property bool enabled
        onExited: if (enabled !== root.active) scope.updateKeys()
    }
    function updateKeys(): void {
        if (keyLease.running) return;
        keyLease.enabled=root.active;
        keyLease.exec(["hyprctl", "eval", "if _G.caelestiaCaptureKeys then _G.caelestiaCaptureKeys(" + (root.active ? "true" : "false") + ") end"]);
    }
    Timer { interval: 700; running: root.active; repeat: true; onTriggered: scope.updateKeys() }
    Process {
        id: photoSaver
        property bool ocr: false
        onExited: code => {
            if (code !== 0 && !ocr) Quickshell.execDetached(["notify-send", "-u", "critical", "Fotoğraf kaydedilemedi / kopyalanamadı", "Disk ve pano erişimini kontrol edin. Yakalama dosyası korundu."]);
        }
    }
    Connections {
        target: recorder
        function onPausedChanged(): void {
            if (root.waitForPause && recorder.paused) { root.waitForPause = false; root.activeAsync = true; }
        }
        function onErrorChanged(): void {
            if (recorder.error) Quickshell.execDetached(["notify-send", "-u", "critical", "Yakalama hatası", recorder.error]);
        }
    }

    LazyLoader {
        id: root
        property bool freeze: true
        property bool closing: false
        property bool video: false
        property bool ocr: false
        property bool sound: true
        property string captureWindow: "{}"
        property string selectedOutput: ""
        property bool resumeOnClose: false
        property bool waitForPause: false
        property var activePicker: null
        onActiveChanged: scope.updateKeys()
        readonly property var recording: recorder
        readonly property var saver: photoSaver

        function open(frozen = true, clipboard = false, textMode = false): void {
            // ponytail: share the existing picker; simultaneous OCR needs a separate still-capture session.
            if (textMode && recorder.recording) {
                Quickshell.execDetached(["notify-send", "Ekrandan yazı kopyala", "Önce devam eden ekran kaydını bitirin."]);
                return;
            }
            if (waitForPause) { waitForPause = false; resumeOnClose = false; recorder.setPaused(false); return; }
            if (active) {
                if (activePicker?.liveAdjust) activePicker.showControls();
                else dismiss();
                return;
            }
            captureWindow = JSON.stringify(Hypr.activeToplevel?.lastIpcObject ?? {});
            freeze = frozen;
            ocr = textMode;
            closing = false;
            video = recorder.recording;
            resumeOnClose = recorder.recording && !recorder.paused;
            selectedOutput = Hypr.focusedMonitor?.name ?? Screens.screens[0]?.name ?? "";
            if (resumeOnClose && !recorder.busy) { waitForPause = true; recorder.setPaused(true); return; }
            activeAsync = true;
        }
        function dismiss(): void {
            const selection = activePicker?.source();
            if (recorder.recording && !recorder.busy) {
                if (selection) recorder.applySelection(selection, resumeOnClose ? false : recorder.paused);
                else if (resumeOnClose) recorder.setPaused(false);
            }
            resumeOnClose = false;
            activeAsync = false;
        }
        function hideForCapture(): void {
            resumeOnClose = false;
            activeAsync = false;
        }

        Variants {
            model: Screens.screens
            StyledWindow {
                id: win
                required property ShellScreen modelData
                screen: modelData
                name: "area-picker"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true
                Picker { loader: root; screen: win.modelData }
            }
        }
    }
    IpcHandler {
        target: "picker"
        function open(): void { root.open(false, false); }
        function openFreeze(): void { root.open(true, false); }
        function openClip(): void { root.open(false, false); }
        function openFreezeClip(): void { root.open(true, false); }
        function openText(): void { root.open(true, false, true); }
        function openVideo(): void { if (!root.active) root.open(true, false); root.video = true; }
        function status(): string { return JSON.stringify({open:root.active,ocr:root.ocr,recording:recorder.recording,paused:recorder.paused,busy:recorder.busy,source:recorder.source,selection:root.activePicker?.source(),error:recorder.error,saved:recorder.saved}); }
        function adjust(dx: int, dy: int, resize: bool): void { root.activePicker?.adjust(dx, dy, resize); }
        function capture(): void { root.activePicker?.capture(); }
        function stop(): void { recorder.stop(); root.resumeOnClose = false; root.activeAsync = false; }
        function pause(): void { recorder.togglePause(); }
        function record(source: string): void { const data=JSON.parse(source); recorder.start(data,data.sound ?? true); }
    }
    CustomShortcut { name: "screenshot"; description: "Open capture tool"; onPressed: root.open(false, false) }
    CustomShortcut { name: "screenshotFreeze"; description: "Open capture tool"; onPressed: root.open(true, false) }
    CustomShortcut { name: "screenshotClip"; description: "Open capture tool"; onPressed: root.open(false, false) }
    CustomShortcut { name: "screenshotFreezeClip"; description: "Open capture tool"; onPressed: root.open(true, false) }
}
