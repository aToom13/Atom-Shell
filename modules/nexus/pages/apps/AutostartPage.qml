pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property list<var> entries: []
    property string editingId
    property string deletingId
    property string errorText
    property bool showPicker
    property bool busy: action.running || listing.running
    readonly property list<string> helper: ["python3", Paths.toLocalFile(Qt.resolvedUrl("../../../../utils/autostart.py"))]

    title: qsTr("Autostart applications")
    isSubPage: true
    Component.onCompleted: listing.running = true

    function clearEditor(): void {
        editingId = "";
        entryName.text = entryCommand.text = "";
        workingDirectory.text = "";
        terminalOption.checked = false;
        enabledOption.checked = true;
    }

    function perform(args: var): void {
        if (busy)
            return;
        errorText = "";
        deletingId = "";
        action.command = [...helper, ...args];
        action.running = true;
    }

    property Process listProcess: Process {
        id: listing
        command: [...root.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.entries = JSON.parse(text); }
                catch (error) { root.errorText = qsTr("Could not read startup applications"); }
            }
        }
        stderr: StdioCollector { id: listError }
        onExited: code => { if (code !== 0) root.errorText = listError.text.trim(); }
    }

    property Process actionProcess: Process {
        id: action
        stderr: StdioCollector { id: actionError }
        onExited: code => {
            if (code === 0) {
                if (["save", "add-app"].includes(command[2]) || (command[2] === "delete" && root.editingId === command[3]))
                    root.clearEditor();
            } else {
                root.errorText = actionError.text.trim() || qsTr("Could not save startup applications");
            }
            listing.running = true;
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.medium
            text: qsTr("These apps start when you sign in. Changes apply to your next session; apps running now are unaffected.")
            wrapMode: Text.WordWrap
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.errorText !== ""
            text: root.errorText
            wrapMode: Text.WrapAnywhere
            color: Colours.palette.m3error
            font: Tokens.font.body.small
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            StyledText { Layout.fillWidth: true; text: qsTr("Your startup apps"); font: Tokens.font.label.medium; color: Colours.palette.m3onSurfaceVariant }
            IconButton {
                icon: "refresh"
                type: IconButton.Text
                disabled: root.busy
                Accessible.name: qsTr("Refresh startup applications")
                onClicked: { root.errorText = ""; listing.running = true; }
            }
        }

        Repeater {
            model: root.entries
            ConnectedRect {
                id: entry
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: index === root.entries.length - 1
                implicitHeight: entryLayout.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: entryLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: entry.modelData.name; font: Tokens.font.body.medium; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; text: entry.modelData.command; font: Tokens.font.label.small; color: Colours.palette.m3outline; elide: Text.ElideRight }
                        StyledText {
                            text: entry.modelData.enabled ? qsTr("Starts at sign-in") : qsTr("Disabled")
                            font: Tokens.font.label.small
                            color: entry.modelData.enabled ? Colours.palette.m3primary : Colours.palette.m3outline
                        }
                    }
                    IconButton {
                        icon: "edit"
                        type: IconButton.Text
                        disabled: root.busy
                        Accessible.name: qsTr("Edit %1").arg(entry.modelData.name)
                        onClicked: {
                            root.editingId = entry.modelData.id;
                            entryName.text = entry.modelData.name;
                            entryCommand.text = entry.modelData.command;
                            workingDirectory.text = entry.modelData.directory;
                            terminalOption.checked = entry.modelData.terminal;
                            enabledOption.checked = entry.modelData.enabled;
                            entryName.forceActiveFocus();
                        }
                    }
                    IconButton {
                        icon: root.deletingId === entry.modelData.id ? "check" : "delete"
                        type: IconButton.Text
                        disabled: root.busy
                        Accessible.name: qsTr("Remove %1 from startup").arg(entry.modelData.name)
                        onClicked: {
                            if (root.deletingId === entry.modelData.id)
                                root.perform(["delete", entry.modelData.id]);
                            else
                                root.deletingId = entry.modelData.id;
                        }
                    }
                    StyledSwitch {
                        checked: entry.modelData.enabled
                        disabled: root.busy
                        Accessible.name: qsTr("Start %1 at sign-in").arg(entry.modelData.name)
                        onToggled: root.perform(["toggle", entry.modelData.id, checked ? "true" : "false"])
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.deletingId !== ""
            text: qsTr("Press the check mark to remove this startup entry. The application stays installed.")
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.busy && root.entries.length === 0
            text: qsTr("No startup apps yet. Choose an installed app or add a command below.")
            font: Tokens.font.body.small
            color: Colours.palette.m3outline
            wrapMode: Text.WordWrap
        }

        SectionHeader { text: qsTr("Add an application") }

        NavRow {
            first: true
            last: true
            text: qsTr("Choose an installed app")
            icon: "apps"
            enabled: !root.busy
            onClicked: root.showPicker = !root.showPicker
        }
        ConnectedRect {
            Layout.fillWidth: true
            visible: root.showPicker
            first: true
            last: true
            implicitHeight: pickerLayout.implicitHeight + Tokens.padding.medium * 2
            ColumnLayout {
                id: pickerLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small
                StyledTextField { id: search; Layout.fillWidth: true; placeholderText: qsTr("Search apps"); leadingIcon: "search" }
                    VerticalFadeListView {
                        id: apps
                        Layout.fillWidth: true
                        Layout.preferredHeight: 240
                        clip: true
                        model: [...DesktopEntries.applications.values].filter(app => app.name.toLowerCase().includes(search.text.toLowerCase())).sort((a, b) => a.name.localeCompare(b.name))
                        delegate: StateLayer {
                            id: appItem
                            required property DesktopEntry modelData
                            anchors.fill: undefined
                            width: apps.width
                            implicitHeight: appLabel.implicitHeight + Tokens.padding.medium * 2
                            Accessible.name: modelData.name
                            onClicked: {
                                root.showPicker = false;
                                root.perform(["add-app", modelData.id + ".desktop"]);
                            }
                            StyledText {
                                id: appLabel
                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                text: appItem.modelData.name
                                elide: Text.ElideRight
                                font: Tokens.font.body.small
                            }
                        }
                    }
            }
        }

        SectionHeader { text: root.editingId ? qsTr("Edit startup command") : qsTr("Or add a command") }
        StyledTextField { id: entryName; Layout.fillWidth: true; placeholderText: qsTr("Name"); leadingIcon: "label" }
        StyledTextField {
            id: entryCommand
            Layout.fillWidth: true
            placeholderText: qsTr("Command")
            leadingIcon: "terminal"
            supportingText: qsTr("Executable and arguments. Example: /usr/bin/9router --tray --skip-update")
        }
        StyledTextField {
            id: workingDirectory
            Layout.fillWidth: true
            placeholderText: qsTr("Working folder (optional)")
            leadingIcon: "folder"
            supportingText: qsTr("Leave empty to use your home folder")
        }
        ToggleRow {
            id: terminalOption
            first: true
            text: qsTr("Run in terminal (Kitty)")
            subtext: qsTr("Show a terminal window for interactive commands")
        }
        ToggleRow {
            id: enabledOption
            last: true
            checked: true
            text: qsTr("Start at sign-in")
            subtext: qsTr("Enable this entry for your next session")
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            TextButton { visible: root.editingId !== ""; text: qsTr("Cancel"); type: TextButton.Text; onClicked: root.clearEditor() }
            IconTextButton {
                icon: root.editingId ? "save" : "add"
                text: root.editingId ? qsTr("Save changes") : qsTr("Add command")
                type: ButtonBase.Filled
                disabled: root.busy || !entryName.text.trim() || !entryCommand.text.trim()
                onClicked: root.perform(["save", root.editingId, entryName.text, entryCommand.text, JSON.stringify({directory: workingDirectory.text, terminal: terminalOption.checked, enabled: enabledOption.checked})])
            }
        }
    }
}
