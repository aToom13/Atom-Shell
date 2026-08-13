pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property string query
    property list<var> customShortcuts: []
    property string editingId
    property bool customActionRunning

    function parseCustom(text: string): list<var> {
        return text.trim().split("\n").filter(line => line).map(line => {
            const fields = line.split("\t");
            return { id: fields[0] ?? "", key: fields[1] ?? "", description: fields[2] ?? "", command: fields[3] ?? "" };
        });
    }

    function refreshCustom(): void {
        customListProc.running = true;
    }

    function editCustom(item: var): void {
        editingId = item.id;
        shortcutKey.text = item.key;
        shortcutDescription.text = item.description;
        shortcutCommand.text = item.command;
        shortcutKey.forceActiveFocus();
    }

    function clearEditor(): void {
        editingId = "";
        shortcutKey.text = shortcutDescription.text = shortcutCommand.text = "";
    }

    function saveCustom(): void {
        if (customActionRunning || !shortcutKey.text.trim() || !shortcutDescription.text.trim() || !shortcutCommand.text.trim())
            return;
        customActionRunning = true;
        customAction.command = [`${Paths.home}/.config/hypr/scripts/manage-shortcut.sh`, "upsert", editingId, shortcutKey.text.trim(), shortcutDescription.text.trim(), shortcutCommand.text.trim()];
        customAction.running = true;
    }

    function deleteCustom(id: string): void {
        if (customActionRunning)
            return;
        customActionRunning = true;
        customAction.command = [`${Paths.home}/.config/hypr/scripts/manage-shortcut.sh`, "delete", id];
        customAction.running = true;
    }

    function matches(entry: var): bool {
        const q = query.trim().toLowerCase();
        return !q || `${entry[0]} ${entry[1]}`.toLowerCase().includes(q);
    }

    readonly property list<var> groups: [
        {
            title: qsTr("Applications & shell"), icon: "apps", entries: [
                ["Super", qsTr("Application launcher")],
                ["Super + W", qsTr("Web browser")],
                ["Super + T", qsTr("Terminal")],
                ["Super + C", qsTr("Code editor")],
                ["Super + E", qsTr("File manager")],
                ["Ctrl + Alt + V", qsTr("Advanced audio settings")],
                ["Super + N", qsTr("Notification sidebar")],
                ["Ctrl + Alt + C", qsTr("Clear notifications")],
                ["Super + K", qsTr("Toggle launcher, dashboard and utilities")],
                ["Ctrl + Alt + Delete / Alt + F4", qsTr("Session and power menu")],
                ["Super + L", qsTr("Lock screen")],
                ["Super + Alt + L", qsTr("Restore shell and lock")],
                ["Super + Shift + H", qsTr("Keyboard shortcut guide")],
                ["Ctrl + Super + Shift + R", qsTr("Stop CaelestiaShell")],
                ["Ctrl + Super + Alt + R", qsTr("Restart CaelestiaShell")]
            ]
        },
        {
            title: qsTr("Windows"), icon: "select_window", entries: [
                ["Super + Q", qsTr("Close active window")],
                ["Super + F", qsTr("Fullscreen")],
                ["Super + Alt + F", qsTr("Maximise with borders")],
                ["Super + Alt + Space", qsTr("Toggle floating")],
                ["Super + P", qsTr("Pin floating window")],
                ["Super + Alt + Backslash", qsTr("Picture-in-picture mode")],
                ["Super + arrows", qsTr("Move focus by direction")],
                ["Super + Shift + arrows", qsTr("Move window by direction")],
                ["Super + - / =", qsTr("Decrease / increase width")],
                ["Super + Shift + - / =", qsTr("Decrease / increase height")],
                ["Super + Alt + arrows", qsTr("Resize in four directions")],
                ["Ctrl + Super + Backslash", qsTr("Centre window")],
                ["Ctrl + Super + Alt + Backslash", qsTr("Resize to 55×70% and centre")],
                ["Super + Z / Super + left drag", qsTr("Move window with pointer")],
                ["Super + X / Super + right drag", qsTr("Resize window with pointer")],
                ["Super + Tab", qsTr("Window overview across workspaces")]
            ]
        },
        {
            title: qsTr("Workspaces"), icon: "grid_view", entries: [
                ["Super + 0–9", qsTr("Open workspace 1–10")],
                ["Super + Alt + 0–9", qsTr("Move window to workspace 1–10")],
                ["Ctrl + Super + 0–9", qsTr("Open workspace group 1–10")],
                ["Ctrl + Super + Alt + 0–9", qsTr("Move window to workspace group 1–10")],
                ["Ctrl + Super + ← / →", qsTr("Previous / next workspace")],
                ["Super + Page Up / Down", qsTr("Previous / next workspace")],
                ["Super + wheel", qsTr("Previous / next workspace")],
                ["Ctrl + Super + wheel", qsTr("Previous / next workspace group")],
                ["Super + Alt + Page Up / Down", qsTr("Move window to adjacent workspace")],
                ["Super + Alt + wheel", qsTr("Move window to adjacent workspace")],
                ["Ctrl + Super + Shift + ← / →", qsTr("Move window to adjacent workspace")],
                ["Ctrl + Super + Shift + ↑", qsTr("Move window to scratch workspace")],
                ["Ctrl + Super + Shift + ↓", qsTr("Move window back to current workspace")],
                ["Super + Alt + S", qsTr("Move window to scratch workspace")]
            ]
        },
        {
            title: qsTr("Window groups"), icon: "tab", entries: [
                ["Alt + Tab", qsTr("Next window in group")],
                ["Shift + Alt + Tab", qsTr("Previous window in group")],
                ["Ctrl + Alt + Tab", qsTr("Next group tab")],
                ["Ctrl + Shift + Alt + Tab", qsTr("Previous group tab")],
                ["Super + ,", qsTr("Create or dissolve window group")],
                ["Super + U", qsTr("Remove window from group")],
                ["Super + Shift + ,", qsTr("Lock active group")]
            ]
        },
        {
            title: qsTr("Special workspaces"), icon: "view_carousel", entries: [
                ["Super + S", qsTr("Scratch workspace")],
                ["Super + D", qsTr("Communication — Equibop / Discord")],
                ["Super + M", qsTr("Music — Spotify")],
                ["Super + G", qsTr("Games — Steam")],
                ["Super + R", qsTr("Todo workspace")],
                ["Ctrl + Shift + Esc", qsTr("System monitor workspace")]
            ]
        },
        {
            title: qsTr("Capture & utilities"), icon: "construction", entries: [
                ["Print", qsTr("Focused-output screenshot, save and copy")],
                ["Super + Shift + S", qsTr("Frozen area screenshot")],
                ["Super + Shift + Alt + S", qsTr("Live area screenshot")],
                ["Super + Alt + R", qsTr("Start area recording")],
                ["Ctrl + Alt + R", qsTr("Start full recording")],
                ["Super + Shift + Alt + R", qsTr("Stop recording")],
                ["Super + Shift + C", qsTr("Colour picker and copy")],
                ["Super + V", qsTr("Clipboard history")],
                ["Super + Alt + V", qsTr("Clipboard history with delete mode")],
                ["Ctrl + Shift + Alt + V", qsTr("Type most recent clipboard entry")],
                ["Super + .", qsTr("Emoji and glyph picker")],
                ["Super + Shift + L", qsTr("Suspend then hibernate")],
                ["Super + Alt + F12", qsTr("Send test notification")]
            ]
        },
        {
            title: qsTr("Media, sound & brightness"), icon: "tune", entries: [
                ["XF86 Audio Play / Pause", qsTr("Play or pause media")],
                ["Ctrl + Super + Space", qsTr("Play or pause media")],
                ["XF86 Audio Next / Ctrl + Super + =", qsTr("Next track")],
                ["XF86 Audio Previous / Ctrl + Super + -", qsTr("Previous track")],
                ["XF86 Audio Stop", qsTr("Stop media")],
                ["XF86 Volume Up / Down", qsTr("Change output volume")],
                ["XF86 Audio Mute / Super + Shift + M", qsTr("Mute output")],
                ["XF86 Mic Mute", qsTr("Mute microphone")],
                ["XF86 Brightness Up / Down", qsTr("Change display brightness")]
            ]
        },
        {
            title: qsTr("Touchpad gestures"), icon: "gesture", entries: [
                ["4-finger horizontal swipe", qsTr("Switch workspace")],
                ["3-finger swipe up", qsTr("Open scratch workspace")],
                ["3-finger swipe down", qsTr("Toggle scratch workspace")],
                ["4-finger swipe down", qsTr("Suspend then hibernate")]
            ]
        }
    ]

    title: qsTr("Keyboard shortcuts")

    Component.onCompleted: refreshCustom()

    property Process customListProcess: Process {
        id: customListProc
        command: [`${Paths.home}/.config/hypr/scripts/manage-shortcut.sh`, "list"]
        stdout: StdioCollector { onStreamFinished: root.customShortcuts = root.parseCustom(text) }
    }

    property Process customActionProcess: Process {
        id: customAction
        stderr: StdioCollector { id: customError }
        onExited: code => {
            root.customActionRunning = false;
            if (code === 0) {
                Quickshell.execDetached(["hyprctl", "reload"]);
                Toaster.toast(qsTr("Shortcut saved"), qsTr("Hyprland keybindings were reloaded"), "keyboard");
                root.clearEditor();
                root.refreshCustom();
            } else {
                Toaster.toast(qsTr("Shortcut error"), customError.text.trim() || qsTr("Could not save the shortcut"), "error");
            }
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Custom shortcuts")
        }

        Repeater {
            model: root.customShortcuts

            delegate: ConnectedRect {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: false
                implicitHeight: customRow.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: customRow
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    MaterialIcon { text: "keyboard_command_key"; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.small }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: modelData.description; font: Tokens.font.body.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; text: modelData.command; color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideRight }
                    }
                    StyledText { text: modelData.key; color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.body.small }
                    IconButton { icon: "edit"; type: IconButton.Text; onClicked: root.editCustom(modelData) }
                    IconButton { icon: "delete"; type: IconButton.Text; onClicked: root.deleteCustom(modelData.id) }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: root.customShortcuts.length === 0
            last: true
            implicitHeight: editorLayout.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: editorLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium
                    StyledTextField { id: shortcutKey; Layout.fillWidth: true; placeholderText: qsTr("Key combination"); leadingIcon: "keyboard"; supportingText: qsTr("Example: SUPER + SHIFT + Y") }
                    StyledTextField { id: shortcutDescription; Layout.fillWidth: true; placeholderText: qsTr("Description"); leadingIcon: "label"; supportingText: qsTr("What this shortcut does") }
                }
                StyledTextField { id: shortcutCommand; Layout.fillWidth: true; placeholderText: qsTr("Command"); leadingIcon: "terminal"; supportingText: qsTr("Shell command executed by Hyprland") }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Tokens.spacing.medium
                    TextButton { visible: root.editingId; text: qsTr("Cancel edit"); type: TextButton.Text; onClicked: root.clearEditor() }
                    IconTextButton {
                        icon: root.editingId ? "save" : "add"
                        text: root.editingId ? qsTr("Save shortcut") : qsTr("Add shortcut")
                        type: ButtonBase.Filled
                        disabled: root.customActionRunning || !shortcutKey.text.trim() || !shortcutDescription.text.trim() || !shortcutCommand.text.trim()
                        onClicked: root.saveCustom()
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            first: true
            last: true
            implicitHeight: advancedEditorLayout.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: advancedEditorLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium
                MaterialIcon { text: "keyboard_settings"; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.medium }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { Layout.fillWidth: true; text: qsTr("Edit built-in shortcuts"); font: Tokens.font.body.medium }
                    StyledText { Layout.fillWidth: true; text: qsTr("Override existing bindings, choose Hyprland dispatchers and configure flags"); color: Colours.palette.m3outline; font: Tokens.font.label.small; wrapMode: Text.WordWrap }
                }
                IconTextButton {
                    icon: "open_in_new"
                    text: qsTr("Advanced editor")
                    type: ButtonBase.Filled
                    onClicked: Quickshell.execDetached(["hyprmod"])
                }
            }
        }

        SectionHeader { text: qsTr("Built-in shortcuts") }

        StyledTextField {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.large
            placeholderText: qsTr("Search shortcuts")
            leadingIcon: "search"
            trailingIcon: text ? "close" : ""
            onTextChanged: root.query = text
        }

        Repeater {
            model: root.groups

            delegate: ColumnLayout {
                id: group
                required property var modelData
                required property int index

                readonly property bool hasMatches: modelData.entries.some(e => root.matches(e))
                Layout.fillWidth: true
                visible: hasMatches
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: group.index === 0
                    text: group.modelData.title
                }

                Repeater {
                    model: group.modelData.entries
                    delegate: InfoRow {
                        required property var modelData
                        required property int index
                        visible: root.matches(modelData)
                        first: index === 0
                        last: index === group.modelData.entries.length - 1
                        icon: group.modelData.icon
                        label: modelData[1]
                        value: modelData[0]
                    }
                }
            }
        }
    }
}
