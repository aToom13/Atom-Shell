pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Scope {
    id: root
    property var status: ({ phase: "idle" })
    property bool dismissed
    property bool locked: false
    property double now: Date.now()
    readonly property bool recording: status.phase === "recording"
    readonly property bool busy: recording || status.phase === "processing"
    readonly property bool visible: !dismissed && status.phase !== "idle"
    readonly property int seconds: Math.max(0, Math.floor(now / 1000 - (status.started || now / 1000)))
    readonly property var output: Quickshell.screens.find(screen => screen.name === status.screen) ?? Quickshell.screens[0]

    function act(action: string): void {
        Quickshell.execDetached(["python3", `${Paths.home}/.config/hypr/scripts/desktop-assist.py`, action]);
    }

    onStatusChanged: { dismissed = false; now = Date.now(); }
    onLockedChanged: if (locked && recording) act("stop")
    Timer { interval: 1000; running: root.recording; repeat: true; onTriggered: root.now = Date.now() }
    Timer { interval: 3500; running: root.visible && !root.busy; onTriggered: root.dismissed = true }

    FileView {
        id: stateFile
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/desktop-assist/stt.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.status = JSON.parse(text()); }
            catch (error) { root.status = { phase: "idle" }; }
        }
    }

    Process {
        command: ["python3", `${Paths.home}/.config/hypr/scripts/desktop-assist.py`, "init"]
        running: true
        onExited: stateFile.reload()
    }

    PanelWindow {
        id: panel
        screen: root.output
        visible: root.visible && !root.locked
        color: "transparent"
        implicitWidth: 360
        implicitHeight: 76
        anchors.bottom: true
        margins.bottom: 36
        WlrLayershell.namespace: "caelestia-dictation"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        contentItem.Config.screen: screen?.name ?? ""
        contentItem.Tokens.screen: screen?.name ?? ""

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: 24
            color: Colours.palette.m3surfaceContainerHigh
            border.width: 1
            border.color: root.recording ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                MaterialIcon {
                    text: root.recording ? "mic" : root.status.phase === "processing" ? "graphic_eq" : root.status.phase === "error" ? "error" : "check_circle"
                    color: root.status.phase === "error" ? Colours.palette.m3error : Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.large
                    SequentialAnimation on opacity {
                        running: root.busy
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 600 }
                        NumberAnimation { to: 1; duration: 600 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: root.recording ? I18n.t("Listening · %1:%2", Math.floor(root.seconds / 60), String(root.seconds % 60).padStart(2, "0"))
                            : root.status.phase === "processing" ? root.status.message || I18n.t("Transcribing…") : root.status.message || ""
                        font: Tokens.font.body.medium
                        elide: Text.ElideRight
                        Accessible.name: text
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.recording ? I18n.t("F10 finish · Max 5 min") : root.status.phase === "processing" ? root.status.correcting ? I18n.t("Turkish · local spelling correction") : I18n.t("Turkish · local Whisper") : I18n.t("Speech to text")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    visible: root.recording
                    icon: "stop"
                    type: IconButton.Tonal
                    Accessible.name: I18n.t("Finish recording and transcribe")
                    onClicked: root.act("stop")
                }
                IconButton {
                    visible: root.busy
                    icon: "close"
                    type: IconButton.Text
                    Accessible.name: I18n.t("Cancel dictation")
                    onClicked: root.act("cancel")
                }
            }
        }
    }
}
