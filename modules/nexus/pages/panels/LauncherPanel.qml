pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property int editingActionIndex: -1

    function commandToText(command: var): string {
        if (!Array.isArray(command))
            return String(command ?? "");
        return command[0] === "sh" && command[1] === "-c" ? (command[2] ?? "") : command.join(" ");
    }

    function cloneAction(action: var): var {
        const copy = {};
        for (const key in action)
            copy[key] = action[key];
        return copy;
    }

    function setActionEnabled(index: int, enabled: bool): void {
        GlobalConfig.launcher.actions = GlobalConfig.launcher.actions.map((action, i) => {
            const copy = cloneAction(action);
            if (i === index)
                copy.enabled = enabled;
            return copy;
        });
    }

    function editAction(index: int, action: var): void {
        editingActionIndex = index;
        actionName.text = action.name ?? "";
        actionDescription.text = action.description ?? "";
        actionCommand.text = commandToText(action.command);
        actionName.forceActiveFocus();
    }

    function clearActionEditor(): void {
        editingActionIndex = -1;
        actionName.text = actionDescription.text = actionCommand.text = "";
    }

    function saveAction(): void {
        const name = actionName.text.trim();
        const description = actionDescription.text.trim();
        const command = actionCommand.text.trim();
        if (!name || !command)
            return;
        if (editingActionIndex >= 0) {
            GlobalConfig.launcher.actions = GlobalConfig.launcher.actions.map((action, i) => {
                const copy = cloneAction(action);
                if (i === editingActionIndex) {
                    copy.name = name;
                    copy.description = description;
                    copy.command = ["sh", "-c", command];
                }
                return copy;
            });
        } else {
            GlobalConfig.launcher.actions = [...GlobalConfig.launcher.actions, { name, description, icon: "bolt", command: ["sh", "-c", command], enabled: true }];
        }
        clearActionEditor();
    }

    function removeAction(index: int): void {
        GlobalConfig.launcher.actions = GlobalConfig.launcher.actions.filter((action, i) => i !== index);
        if (editingActionIndex === index)
            clearActionEditor();
    }

    title: qsTr("Launcher")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // General
        SectionHeader {
            first: true
            text: qsTr("General")
        }

        ToggleRow {
            first: true
            text: qsTr("Enabled")
            checked: Config.launcher.enabled
            onToggled: GlobalConfig.launcher.enabled = checked
        }

        ToggleRow {
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal when the cursor reaches the screen edge")
            checked: Config.launcher.showOnHover
            onToggled: GlobalConfig.launcher.showOnHover = checked
        }

        TextFieldRow {
            id: prefixRow

            last: true
            label: qsTr("Action prefix")
            subtext: qsTr("Prefix used to run actions in the launcher")
            errorText: qsTr("Prefix must not be alphanumeric")
            value: GlobalConfig.launcher.actionPrefix === ">" ? "" : GlobalConfig.launcher.actionPrefix // TODO: replace with empty only when not loaded once loaded state is exposed
            placeholderText: ">"
            maximumLength: 1
            smallField: true
            validate: /^[^a-zA-Z0-9\s]$/
            onEditingFinished: value => {
                if (!field.valid)
                    return;
                /// TODO: replace with GlobalConfig.launcher.resetOption("actionPrefix") on empty commit when reset is fixed
                GlobalConfig.launcher.actionPrefix = value || ">";
                if (GlobalConfig.launcher.actionPrefix === ">")
                    clear();
            }
        }

        // Display
        SectionHeader {
            text: qsTr("Display")
        }

        StepperRow {
            first: true
            label: qsTr("Max items shown")
            value: Config.launcher.maxShown
            from: 1
            to: 20
            stepSize: 1
            onMoved: v => GlobalConfig.launcher.maxShown = v
        }

        StepperRow {
            label: qsTr("Max wallpapers")
            value: Config.launcher.maxWallpapers
            from: 1
            to: 30
            stepSize: 1
            onMoved: v => GlobalConfig.launcher.maxWallpapers = v
        }

        StepperRow {
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the launcher opens")
            value: Config.launcher.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.launcher.dragThreshold = v
        }

        // Behaviour
        SectionHeader {
            text: qsTr("Behaviour")
        }

        ToggleRow {
            first: true
            text: qsTr("Vim keybinds")
            subtext: qsTr("Navigate results with Ctrl+hjkl")
            checked: GlobalConfig.launcher.vimKeybinds
            onToggled: GlobalConfig.launcher.vimKeybinds = checked
        }

        ToggleRow {
            text: qsTr("Enable dangerous actions")
            subtext: qsTr("Allow actions that shut down or log out")
            checked: GlobalConfig.launcher.enableDangerousActions
            onToggled: GlobalConfig.launcher.enableDangerousActions = checked
        }

        ConnectedRect {
            Layout.fillWidth: true
            last: true
            implicitHeight: prefixLayout.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: prefixLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledTextField {
                    Layout.fillWidth: true
                    placeholderText: qsTr("Special prefix")
                    supportingText: qsTr("Prefix for special launcher modes")
                    text: GlobalConfig.launcher.specialPrefix
                    onAccepted: GlobalConfig.launcher.specialPrefix = text
                }

                StyledTextField {
                    Layout.fillWidth: true
                    placeholderText: qsTr("Action prefix")
                    supportingText: qsTr("Prefix for shell actions")
                    text: GlobalConfig.launcher.actionPrefix
                    onAccepted: GlobalConfig.launcher.actionPrefix = text
                }
            }
        }

        // Fuzzy search
        SectionHeader {
            text: qsTr("Fuzzy search")
        }

        ToggleRow {
            first: true
            text: qsTr("Apps")
            checked: GlobalConfig.launcher.useFuzzy.apps
            onToggled: GlobalConfig.launcher.useFuzzy.apps = checked
        }

        ToggleRow {
            text: qsTr("Actions")
            checked: GlobalConfig.launcher.useFuzzy.actions
            onToggled: GlobalConfig.launcher.useFuzzy.actions = checked
        }

        ToggleRow {
            text: qsTr("Schemes")
            checked: GlobalConfig.launcher.useFuzzy.schemes
            onToggled: GlobalConfig.launcher.useFuzzy.schemes = checked
        }

        ToggleRow {
            text: qsTr("Variants")
            checked: GlobalConfig.launcher.useFuzzy.variants
            onToggled: GlobalConfig.launcher.useFuzzy.variants = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Wallpapers")
            checked: GlobalConfig.launcher.useFuzzy.wallpapers
            onToggled: GlobalConfig.launcher.useFuzzy.wallpapers = checked
        }

        SectionHeader { text: qsTr("Launcher actions") }

        Repeater {
            model: GlobalConfig.launcher.actions
            delegate: ConnectedRect {
                id: actionRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: index === GlobalConfig.launcher.actions.length - 1
                implicitHeight: actionLayout.implicitHeight + Tokens.padding.medium * 2

                StateLayer { onClicked: root.editAction(actionRow.index, actionRow.modelData) }

                RowLayout {
                    id: actionLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    IconButton {
                        icon: (actionRow.modelData.enabled ?? true) ? "check_circle" : "radio_button_unchecked"
                        type: IconButton.Text
                        onClicked: root.setActionEnabled(actionRow.index, !(actionRow.modelData.enabled ?? true))
                    }
                    MaterialIcon { text: actionRow.modelData.icon ?? "bolt"; color: Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.small }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: actionRow.modelData.name ?? qsTr("Unnamed"); font: Tokens.font.body.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; text: root.commandToText(actionRow.modelData.command); color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideRight }
                    }
                    IconButton { icon: "edit"; type: IconButton.Text; onClicked: root.editAction(actionRow.index, actionRow.modelData) }
                    IconButton { icon: "delete"; type: IconButton.Text; onClicked: root.removeAction(actionRow.index) }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: GlobalConfig.launcher.actions.length === 0
            last: true
            implicitHeight: actionEditorLayout.implicitHeight + Tokens.padding.large * 2
            ColumnLayout {
                id: actionEditorLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium
                    StyledTextField { id: actionName; Layout.fillWidth: true; placeholderText: qsTr("Action name"); leadingIcon: "label" }
                    StyledTextField { id: actionDescription; Layout.fillWidth: true; placeholderText: qsTr("Description"); leadingIcon: "notes" }
                }
                StyledTextField { id: actionCommand; Layout.fillWidth: true; placeholderText: qsTr("Shell command"); leadingIcon: "terminal"; supportingText: qsTr("Executed through sh -c") }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Tokens.spacing.medium
                    TextButton { visible: root.editingActionIndex >= 0; text: qsTr("Cancel edit"); type: TextButton.Text; onClicked: root.clearActionEditor() }
                    IconTextButton {
                        icon: root.editingActionIndex >= 0 ? "save" : "add"
                        text: root.editingActionIndex >= 0 ? qsTr("Save action") : qsTr("Add action")
                        type: ButtonBase.Filled
                        disabled: !actionName.text.trim() || !actionCommand.text.trim()
                        onClicked: root.saveAction()
                    }
                }
            }
        }
    }
}
