pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property list<var> monitors
    property string error
    property bool refreshing

    function refresh(): void {
        refreshing = true;
        monitorProc.running = true;
    }

    function modeFor(monitor: var): string {
        return `${monitor.width}x${monitor.height}@${Number(monitor.refreshRate).toFixed(2)}`;
    }

    function setScale(monitor: var, scale: real): void {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/set-monitor-override.sh",
            monitor.name, modeFor(monitor), `${monitor.x}x${monitor.y}`, scale.toString(), monitor.transform.toString()]);
        refreshTimer.restart();
    }

    title: qsTr("Display")
    Component.onCompleted: refresh()

    property Process monitorProcess: Process {
        id: monitorProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text);
                    root.error = "";
                } catch (e) {
                    root.error = qsTr("Could not parse display information");
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim() }
        onExited: root.refreshing = false
    }

    property Timer refreshDelay: Timer {
        id: refreshTimer
        interval: 1200
        onTriggered: root.refresh()
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledText {
            Layout.fillWidth: true
            visible: !!root.error
            text: root.error
            color: Colours.palette.m3error
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.monitors

            delegate: ConnectedRect {
                id: card
                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: true
                last: true
                implicitHeight: monitorLayout.implicitHeight + Tokens.padding.large * 2

                ColumnLayout {
                    id: monitorLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        MaterialIcon {
                            text: card.modelData.disabled ? "desktop_access_disabled" : card.modelData.focused ? "desktop_windows" : "monitor"
                            color: card.modelData.focused ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.large
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText { text: card.modelData.name; font: Tokens.font.title.small }
                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData.description || qsTr("Unknown display")
                                color: Colours.palette.m3outline
                                elide: Text.ElideRight
                                font: Tokens.font.body.small
                            }
                        }
                        StyledText {
                            text: card.modelData.focused ? qsTr("Primary") : card.modelData.disabled ? qsTr("Disabled") : qsTr("Active")
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    InfoRow {
                        first: true
                        label: qsTr("Resolution")
                        value: root.modeFor(card.modelData)
                    }
                    InfoRow {
                        last: true
                        label: qsTr("Position")
                        value: `${card.modelData.x}, ${card.modelData.y}`
                    }

                    StyledText {
                        text: qsTr("Scale")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.large
                    }
                    RowLayout {
                        spacing: Tokens.spacing.small
                        Repeater {
                            model: [1, 1.25, 1.5, 1.75, 2]
                            delegate: TextButton {
                                required property real modelData
                                text: `${modelData}×`
                                type: Math.abs(card.modelData.scale - modelData) < 0.01 ? TextButton.Filled : TextButton.Tonal
                                onClicked: root.setScale(card.modelData, modelData)
                            }
                        }
                    }
                }
            }
        }

        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "refresh"
            text: qsTr("Refresh displays")
            type: IconTextButton.Tonal
            disabled: root.refreshing
            onClicked: root.refresh()
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Display scale changes are saved per output and restored by Hyprland at login.")
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
        }
    }
}
