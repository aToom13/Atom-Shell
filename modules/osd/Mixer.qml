pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

FocusScope {
    id: root

    required property var controller
    readonly property var entries: [{key: "system", name: qsTr("Sistem"), nodes: Audio.sink ? [Audio.sink] : []}, ...Audio.playbackApps]
    property string selectedKey: "system"
    readonly property int selectedIndex: Math.max(0, entries.findIndex(e => e.key === selectedKey))
    readonly property var selectedEntry: entries[selectedIndex] ?? null
    property bool editing
    property bool outputFocused
    readonly property var selectedOutput: selectedKey === "system" ? Audio.sink : Audio.outputForNodes(selectedEntry?.nodes ?? [])
    property bool choosingDevice
    property var pendingDeviceId: -1
    readonly property int deviceIndex: Math.max(0, Audio.availableSinks.findIndex(n => n.id === pendingDeviceId))

    readonly property int visibleCards: Math.min(entries.length, 4)
    implicitWidth: Math.max(180, visibleCards * 100 + Math.max(0, visibleCards - 1) * Tokens.spacing.small + Tokens.padding.medium * 2)
    implicitHeight: layout.implicitHeight + Tokens.padding.medium * 2
    focus: true

    opacity: 0
    Component.onCompleted: { forceActiveFocus(); opacity = 1; }
    Behavior on opacity { Anim { type: Anim.DefaultEffects } }
    onEntriesChanged: {
        if (!entries.some(e => e.key === selectedKey)) {
            selectedKey = "system";
            editing = false;
            choosingDevice = false;
            outputFocused = false;
        }
    }
    onSelectedIndexChanged: cards.positionViewAtIndex(Math.min(selectedIndex, entries.length - 1), ListView.Contain)

    Connections {
        target: Audio
        function onAvailableSinksChanged(): void {
            if (root.choosingDevice && !Audio.availableSinks.some(n => n.id === root.pendingDeviceId))
                root.pendingDeviceId = Audio.availableSinks[0]?.id ?? -1;
        }
    }

    function selectStep(step: int): void {
        const index = (selectedIndex + step + entries.length) % entries.length;
        selectedKey = entries[index].key;
        editing = false;
    }

    function adjustVolume(direction: int): void {
        if (!selectedEntry)
            return;
        for (const node of selectedEntry.nodes)
            Audio.setStreamVolume(node, (node?.audio?.volume ?? 0) + direction * GlobalConfig.services.audioIncrement);
    }

    function toggleMute(): void {
        if (!selectedEntry)
            return;
        const mute = !selectedEntry.nodes.every(n => n?.audio?.muted);
        for (const node of selectedEntry.nodes)
            Audio.setStreamMuted(node, mute);
    }

    function activate(): void {
        if (outputFocused) {
            if (!Audio.availableSinks.length)
                return;
            choosingDevice = true;
            pendingDeviceId = selectedOutput?.id ?? Audio.availableSinks[0].id;
        } else if (selectedEntry?.nodes.length) {
            editing = !editing;
        }
    }

    function handleKey(key: string): bool {
        if (choosingDevice) {
            if (["Up", "Down", "Left", "Right", "Tab", "Backtab"].includes(key)) {
                if (Audio.availableSinks.length) {
                    const step = ["Up", "Left", "Backtab"].includes(key) ? -1 : 1;
                    pendingDeviceId = Audio.availableSinks[(deviceIndex + step + Audio.availableSinks.length) % Audio.availableSinks.length].id;
                }
            } else if (key === "Return" || key === "Enter") {
                const node = Audio.availableSinks.find(n => n.id === pendingDeviceId);
                if (node?.ready && !Audio.routingBusy) {
                    if (selectedKey === "system") Audio.setAudioSink(node);
                    else Audio.moveApp(selectedEntry?.nodes ?? [], node);
                }
                choosingDevice = false;
            } else if (key === "Escape") {
                choosingDevice = false;
            } else {
                return false;
            }
            return true;
        }
        if (key === "Escape") {
            if (editing) editing = false;
            else if (outputFocused) outputFocused = false;
            else controller.closeMixer();
        } else if (key === "Return" || key === "Enter") {
            activate();
        } else if (key === "M" || key === "Space") {
            toggleMute();
        } else if (key === "Tab" || key === "Backtab") {
            editing = false;
            if (key === "Tab") {
                if (outputFocused) { outputFocused = false; selectStep(1); }
                else outputFocused = true;
            } else {
                if (outputFocused) outputFocused = false;
                else { selectStep(-1); outputFocused = true; }
            }
        } else if (["Up", "Down", "Left", "Right"].includes(key)) {
            const step = ["Up", "Right"].includes(key) ? 1 : -1;
            if (editing) adjustVolume(step);
            else if (key === "Down") outputFocused = true;
            else if (key === "Up") outputFocused = false;
            else { outputFocused = false; selectStep(key === "Right" ? 1 : -1); }
        } else {
            return false;
        }
        return true;
    }

    function status(): var {
        return {selected: selectedKey, editing, choosingDevice, outputFocused, width, height,
            entries: entries.map(e => ({key: e.key, name: e.name, output: (e.key === "system" ? Audio.sink : Audio.outputForNodes(e.nodes))?.id ?? -1, nodes: e.nodes.map(n => ({id: n.id, volume: n.audio?.volume, muted: n.audio?.muted}))})),
            devices: Audio.availableSinks.map(n => ({id: n.id, name: Audio.outputName(n)})),
            currentDevice: selectedOutput?.id ?? -1, defaultDevice: Audio.sink?.id ?? -1, routingBusy: Audio.routingBusy, pendingDevice: pendingDeviceId, focused: activeFocus};
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        const names = {[Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down", [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right",
            [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Backtab", [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Enter",
            [Qt.Key_Escape]: "Escape", [Qt.Key_M]: "M", [Qt.Key_Space]: "Space"};
        event.accepted = !!names[event.key] && root.handleKey(names[event.key]);
    }

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            MaterialIcon { visible: root.width >= 260; text: "instant_mix"; color: Colours.palette.m3primary }
            StyledText {
                Layout.fillWidth: true
                text: qsTr("Ses mikseri")
                wrapMode: Text.WordWrap
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
            }
            IconButton {
                type: IconButton.Text
                icon: "close"
                Accessible.name: qsTr("Ses mikserini kapat")
                onClicked: root.controller.closeMixer()
            }
        }

        ListView {
            id: cards
            Layout.fillWidth: true
            implicitHeight: 244
            orientation: ListView.Horizontal
            spacing: Tokens.spacing.small
            clip: true
            model: root.entries
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: StyledRect {
                id: card
                required property var modelData
                readonly property bool selected: root.selectedKey === modelData.key
                readonly property real volume: modelData.nodes.reduce((v, n) => Math.max(v, n.audio?.volume ?? 0), 0)
                readonly property bool muted: modelData.nodes.length > 0 && modelData.nodes.every(n => n.audio?.muted)
                width: (cards.width - (root.visibleCards - 1) * cards.spacing) / root.visibleCards
                height: cards.height - 12
                radius: Tokens.rounding.large
                color: selected ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh
                border.width: selected && !root.outputFocused ? 2 : 0
                border.color: root.editing ? Colours.palette.m3primary : Colours.palette.m3outline
                Accessible.role: Accessible.Slider
                Accessible.name: modelData.name
                Accessible.description: Math.round(volume * 100) + "%"

                TapHandler {
                    onTapped: {
                        root.selectedKey = card.modelData.key;
                        root.choosingDevice = false;
                        root.outputFocused = false;
                        root.editing = true;
                        root.forceActiveFocus();
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: card.modelData.name
                        elide: Text.ElideRight
                        font: Tokens.font.body.small
                    }

                    CustomMouseArea {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 30
                        implicitHeight: 126
                        enabled: card.modelData.nodes.length > 0
                        onWheel: event => {
                            root.selectedKey = card.modelData.key;
                            root.adjustVolume(event.angleDelta.y > 0 ? 1 : -1);
                        }

                        FilledSlider {
                            anchors.fill: parent
                            value: card.volume
                            to: GlobalConfig.services.maxVolume
                            icon: Icons.getVolumeIcon(card.volume, card.muted)
                            onPressedChanged: {
                                if (pressed) {
                                    root.selectedKey = card.modelData.key;
                                    root.outputFocused = false;
                                    root.editing = true;
                                }
                            }
                            onMoved: {
                                for (const node of card.modelData.nodes)
                                    Audio.setStreamVolume(node, value);
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 2
                        IconButton {
                            type: IconButton.Text
                            icon: card.muted ? "volume_off" : "volume_up"
                            Accessible.name: I18n.t("Toggle mute for %1", card.modelData.name)
                            onClicked: {
                                root.selectedKey = card.modelData.key;
                                root.toggleMute();
                                root.forceActiveFocus();
                            }
                        }
                        StyledText { text: Math.round(card.volume * 100) + "%"; font: Tokens.font.body.small }
                    }
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: outputLayout.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.medium
            color: root.outputFocused ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh
            border.width: root.outputFocused ? 2 : 0
            border.color: Colours.palette.m3outline
            Accessible.role: Accessible.Button
            Accessible.name: I18n.t("Output device")

            TapHandler {
                onTapped: {
                    root.outputFocused = true;
                    root.activate();
                    root.forceActiveFocus();
                }
            }

            RowLayout {
                id: outputLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                MaterialIcon { text: "speaker" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedEntry?.name ?? I18n.t("Output")
                        elide: Text.ElideRight
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Audio.outputName(root.selectedOutput)
                        elide: Text.ElideRight
                    }
                }
                MaterialIcon { text: root.choosingDevice ? "expand_less" : "chevron_right" }
            }
        }

        ListView {
            id: devices
            Layout.fillWidth: true
            visible: root.choosingDevice
            implicitHeight: visible ? Math.min(contentHeight, 176) : 0
            clip: true
            spacing: Tokens.spacing.extraSmall
            model: Audio.availableSinks
            currentIndex: root.deviceIndex
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: StyledRect {
                id: device
                required property var modelData
                required property int index
                width: devices.width
                height: 48
                radius: Tokens.rounding.small
                color: index === root.deviceIndex ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh
                border.width: index === root.deviceIndex ? 1 : 0
                border.color: Colours.palette.m3primary
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.description
                Accessible.checked: root.selectedOutput?.id === modelData.id
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    StyledText {
                        Layout.fillWidth: true
                        text: Audio.outputName(device.modelData)
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                    }
                    MaterialIcon { text: root.selectedOutput?.id === device.modelData.id ? "check_circle" : "radio_button_unchecked" }
                }
                TapHandler {
                    onTapped: {
                        root.pendingDeviceId = device.modelData.id;
                        root.handleKey("Return");
                        root.forceActiveFocus();
                    }
                }
            }
        }

    }
}
