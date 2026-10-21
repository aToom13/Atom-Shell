pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property int editingActionIndex: -1
    property int editingFolderIndex: -1
    property string folderAppSearch
    property var folderApps: []

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

    function editFolder(index: int, folder: var): void {
        editingFolderIndex = index;
        folderName.text = folder.name ?? "";
        folderIcon.text = folder.icon ?? "folder";
        folderApps = [...(folder.apps ?? [])];
        folderAppSearch = "";
        folderName.forceActiveFocus();
    }

    function clearFolderEditor(): void {
        editingFolderIndex = -1;
        folderName.text = "";
        folderIcon.text = "folder";
        folderApps = [];
        folderAppSearch = "";
    }

    function toggleFolderApp(appId: string): void {
        folderApps = folderApps.includes(appId) ? folderApps.filter(id => id !== appId) : [...folderApps, appId];
    }

    function filteredFolderApps(): var {
        const query = folderAppSearch.trim().toLowerCase();
        if (!query)
            return [];
        return [...DesktopEntries.applications.values].filter(app => `${app.name} ${app.id} ${app.comment || ""}`.toLowerCase().includes(query)).sort((a, b) => a.name.localeCompare(b.name)).slice(0, 8);
    }

    function saveFolder(): void {
        const name = folderName.text.trim();
        if (!name || folderApps.length === 0)
            return;
        const folder = {
            id: editingFolderIndex >= 0 ? LauncherFolders.folders[editingFolderIndex].id : Date.now().toString(),
            name,
            icon: folderIcon.text.trim() || "folder",
            apps: folderApps
        };
        const folders = [...LauncherFolders.folders];
        if (editingFolderIndex >= 0)
            folders[editingFolderIndex] = folder;
        else
            folders.push(folder);
        LauncherFolders.save(folders);
        clearFolderEditor();
    }

    function removeFolder(index: int): void {
        LauncherFolders.save(LauncherFolders.folders.filter((folder, i) => i !== index));
        if (editingFolderIndex === index)
            clearFolderEditor();
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

        SectionHeader { text: qsTr("Application folders") }

        Repeater {
            model: LauncherFolders.folders
            delegate: ConnectedRect {
                id: folderRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: index === LauncherFolders.folders.length - 1
                implicitHeight: folderLayout.implicitHeight + Tokens.padding.medium * 2

                StateLayer { onClicked: root.editFolder(folderRow.index, folderRow.modelData) }

                RowLayout {
                    id: folderLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    MaterialIcon { text: folderRow.modelData.icon || "folder"; color: Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.medium }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: folderRow.modelData.name; font: Tokens.font.body.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; text: qsTr("%1 applications").arg(folderRow.modelData.apps.length); color: Colours.palette.m3outline; font: Tokens.font.label.small }
                    }
                    IconButton { icon: "edit"; type: IconButton.Text; onClicked: root.editFolder(folderRow.index, folderRow.modelData) }
                    IconButton { icon: "delete"; type: IconButton.Text; onClicked: root.removeFolder(folderRow.index) }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: LauncherFolders.folders.length === 0
            last: true
            implicitHeight: folderEditorLayout.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: folderEditorLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium
                    StyledTextField { id: folderName; Layout.fillWidth: true; placeholderText: qsTr("Folder name"); leadingIcon: "folder" }
                    StyledTextField { id: folderIcon; Layout.fillWidth: true; placeholderText: qsTr("Material icon"); text: "folder"; leadingIcon: "symbols" }
                }

                StyledTextField {
                    Layout.fillWidth: true
                    placeholderText: qsTr("Search applications")
                    supportingText: qsTr("%1 selected").arg(root.folderApps.length)
                    leadingIcon: "search"
                    text: root.folderAppSearch
                    onTextChanged: root.folderAppSearch = text
                }

                Repeater {
                    model: root.filteredFolderApps()

                    delegate: ConnectedRect {
                        id: appItem
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: appLayout.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.small

                        StateLayer {
                            radius: appItem.radius
                            onClicked: root.toggleFolderApp(appItem.modelData.id)
                        }

                        RowLayout {
                            id: appLayout
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            IconImage {
                                asynchronous: true
                                implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.8)
                                source: Quickshell.iconPath(appItem.modelData.icon, "image-missing")
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText { Layout.fillWidth: true; text: appItem.modelData.name; font: Tokens.font.body.small; elide: Text.ElideRight }
                                StyledText { Layout.fillWidth: true; text: appItem.modelData.id; color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideRight }
                            }

                            MaterialIcon {
                                text: root.folderApps.includes(appItem.modelData.id) ? "check_circle" : "radio_button_unchecked"
                                color: root.folderApps.includes(appItem.modelData.id) ? Colours.palette.m3primary : Colours.palette.m3outline
                                fontStyle: Tokens.font.icon.medium
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Tokens.spacing.medium
                    TextButton { visible: root.editingFolderIndex >= 0; text: qsTr("Cancel edit"); type: TextButton.Text; onClicked: root.clearFolderEditor() }
                    IconTextButton {
                        icon: root.editingFolderIndex >= 0 ? "save" : "create_new_folder"
                        text: root.editingFolderIndex >= 0 ? qsTr("Save folder") : qsTr("Add folder")
                        type: ButtonBase.Filled
                        disabled: !folderName.text.trim() || root.folderApps.length === 0
                        onClicked: root.saveFolder()
                    }
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
