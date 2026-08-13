pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Audio")

    property string serverName: qsTr("Detecting…")
    property string sampleSpec: ""

    Component.onCompleted: audioInfoProc.running = true

    property Process audioInfoProcess: Process {
        id: audioInfoProc
        command: ["pactl", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    if (line.startsWith("Server Name:")) root.serverName = line.split(":").slice(1).join(":").trim();
                    if (line.startsWith("Default Sample Specification:")) root.sampleSpec = line.split(":").slice(1).join(":").trim();
                }
            }
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Output
        SliderRow {
            first: true
            icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
            label: qsTr("Output")
            valueLabel: Math.round(value * 100) + "%"
            value: Audio.volume
            enabled: !Audio.muted
            onMoved: v => Audio.setVolume(v)
        }

        ToggleRow {
            text: qsTr("Muted")
            checked: Audio.muted
            onToggled: Audio.setStreamMuted(Audio.sink, checked)
        }

        AudioDeviceList {
            nodes: Audio.sinks
            currentId: Audio.sink?.id ?? -1
            iconName: "speaker"
            placeholderIcon: "speaker"
            placeholderText: qsTr("No output devices")
            onSelected: node => Audio.setAudioSink(node)
        }

        // Input
        SliderRow {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            icon: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
            label: qsTr("Input")
            valueLabel: Math.round(value * 100) + "%"
            value: Audio.sourceVolume
            enabled: !Audio.sourceMuted
            onMoved: v => Audio.setSourceVolume(v)
        }

        ToggleRow {
            text: qsTr("Muted")
            checked: Audio.sourceMuted
            onToggled: Audio.setStreamMuted(Audio.source, checked)
        }

        AudioDeviceList {
            nodes: Audio.sources
            currentId: Audio.source?.id ?? -1
            iconName: "mic"
            placeholderIcon: "mic_off"
            placeholderText: qsTr("No input devices")
            onSelected: node => Audio.setAudioSource(node)
        }

        // Per-app volumes
        NavRow {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            last: true

            icon: "tune"
            text: qsTr("App volumes")
            subtext: Audio.streams.length === 0 ? qsTr("No apps playing audio") : Audio.streams.length === 1 ? qsTr("1 app playing audio") : qsTr("%1 apps playing audio").arg(Audio.streams.length)
            onClicked: root.nState.openSubPage(1)
        }

        SectionHeader { text: qsTr("Volume behaviour") }

        StepperRow {
            first: true
            label: qsTr("Maximum output")
            subtext: qsTr("Upper limit used by the shell controls")
            value: Math.round(GlobalConfig.services.maxVolume * 100)
            from: 50
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.services.maxVolume = v / 100
        }

        StepperRow {
            last: true
            label: qsTr("Volume step")
            subtext: qsTr("Change for media keys and taskbar scrolling")
            value: Math.round(GlobalConfig.services.audioIncrement * 100)
            from: 1
            to: 25
            stepSize: 1
            onMoved: v => GlobalConfig.services.audioIncrement = v / 100
        }

        SectionHeader { text: qsTr("Audio system") }
        InfoRow { first: true; icon: "graphic_eq"; label: qsTr("Sound server"); value: root.serverName }
        InfoRow { last: true; icon: "equalizer"; label: qsTr("Sample format"); value: root.sampleSpec }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.medium

            IconTextButton {
                icon: "tune"
                text: qsTr("Advanced mixer")
                type: ButtonBase.Filled
                onClicked: Quickshell.execDetached(GlobalConfig.general.apps.audio)
            }
            IconTextButton {
                icon: "restart_alt"
                text: qsTr("Restart audio")
                type: IconTextButton.Tonal
                onClicked: Quickshell.execDetached(["sh", "-c", "systemctl --user restart pipewire pipewire-pulse wireplumber"])
            }
        }
    }
}
