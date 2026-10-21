pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common
import "../../../utils/ShortcutSearch.js" as ShortcutSearch

PageBase {
    id: root

    property alias query: searchField.text
    property string category: ""
    property bool showEditor: false
    property list<var> customShortcuts: []
    property string editingId
    property bool customActionRunning
    property var builtinShortcuts: []
    property var editingBindings: []
    property var selectedBuiltin: null
    property string editingBuiltinDescription
    property bool builtinSaving: false
    property bool recordingShortcut: false
    property bool recorderReleasePending: false
    property string builtinError

    readonly property string builtinConflict: {
        if (!selectedBuiltin || !builtinKey.text.trim()) return "";
        const key = ShortcutSearch.canonicalKey(builtinKey.text);
        const conflict = builtinShortcuts.find(binding => binding.original !== selectedBuiltin.original && ShortcutSearch.canonicalKey(binding.key) === key);
        return conflict ? qsTr("Already used: %1").arg(conflict.key) : "";
    }

    function chooseBuiltin(binding: var): void {
        selectedBuiltin = binding;
        builtinKey.text = binding.key;
        builtinError = "";
        recordingShortcut = false;
        recorderReleasePending = false;
    }

    function editBuiltin(entry: var): void {
        editingBuiltinDescription = entry[1];
        editingBindings = entry[4];
        chooseBuiltin(editingBindings[0]);
        showEditor = false;
        root.flickable.contentY = -root.flickable.topMargin;
        Qt.callLater(() => builtinKey.forceActiveFocus());
    }

    function saveBuiltin(reset: bool): void {
        if (!selectedBuiltin || builtinSaving || (!reset && builtinConflict)) return;
        builtinSaving = true;
        builtinError = "";
        builtinAction.command = ["python3", `${Paths.home}/.config/quickshell/caelestia/utils/builtin_shortcuts.py`, reset ? "reset" : "set", selectedBuiltin.original];
        if (!reset) builtinAction.command = [...builtinAction.command, builtinKey.text.trim()];
        builtinAction.running = true;
    }

    function recordKey(event: var): void {
        if (!recordingShortcut) return;
        event.accepted = true;
        if (event.key === Qt.Key_Escape) { recordingShortcut = false; recorderReleasePending = true; return; }
        if ([Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R].includes(event.key)) return;
        const names = {};
        names[Qt.Key_Space] = "space";
        names[Qt.Key_Return] = "Return";
        names[Qt.Key_Enter] = "Return";
        names[Qt.Key_Tab] = "Tab";
        names[Qt.Key_Backtab] = "Tab";
        names[Qt.Key_Backspace] = "BackSpace";
        names[Qt.Key_Delete] = "Delete";
        names[Qt.Key_Insert] = "Insert";
        names[Qt.Key_Home] = "Home";
        names[Qt.Key_End] = "End";
        names[Qt.Key_PageUp] = "Page_Up";
        names[Qt.Key_PageDown] = "Page_Down";
        names[Qt.Key_Left] = "Left";
        names[Qt.Key_Right] = "Right";
        names[Qt.Key_Up] = "Up";
        names[Qt.Key_Down] = "Down";
        const punctuation = { "-": "minus", "=": "equal", "+": "plus", ",": "comma", ".": "period", "\\": "backslash", "/": "slash", ";": "semicolon", "'": "apostrophe", "[": "bracketleft", "]": "bracketright", "`": "grave" };
        let key = names[event.key] || punctuation[event.text];
        if (!key && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35) key = "F" + (event.key - Qt.Key_F1 + 1);
        if (!key && event.key >= Qt.Key_A && event.key <= Qt.Key_Z) key = String.fromCharCode(event.key);
        if (!key && /^[0-9]$/.test(event.text)) key = event.text;
        if (!key && event.text.length === 1) key = "U" + event.text.charCodeAt(0).toString(16).padStart(4, "0").toUpperCase();
        if (!key) { builtinError = qsTr("Type this key name manually."); return; }
        const parts = [];
        if (event.modifiers & Qt.ControlModifier) parts.push("CTRL");
        if (event.modifiers & Qt.MetaModifier) parts.push("SUPER");
        if (event.modifiers & Qt.AltModifier) parts.push("ALT");
        if (event.modifiers & Qt.ShiftModifier) parts.push("SHIFT");
        builtinKey.text = [...parts, key].join(" + ");
        recordingShortcut = false;
        recorderReleasePending = true;
    }

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
        selectedBuiltin = null;
        showEditor = true;
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

    function resetSearch(): void {
        searchField.clear();
        category = "";
        searchField.forceActiveFocus();
    }

    readonly property var allGroups: [...groups.map(group => ShortcutSearch.withBindings(group, builtinShortcuts)), {
        id: "custom", title: qsTr("Custom shortcuts"), icon: "person", keywords: "ozel kisisel custom command komut",
        entries: customShortcuts.map(item => [item.key, item.description, [item.command], item])
    }]
    readonly property var searchGroups: ShortcutSearch.filterGroups(allGroups, query, "")
    readonly property var visibleGroups: searchGroups.filter(group => !category || group.id === category)
    readonly property int resultCount: visibleGroups.reduce((count, group) => count + group.entries.length, 0)
    readonly property int totalCount: allGroups.reduce((count, group) => count + group.entries.length, 0)

    readonly property list<var> groups: ShortcutSearch.catalog()

    title: qsTr("Keyboard shortcuts")

    Component.onCompleted: { query = nState.shortcutQuery; refreshCustom(); builtinListProc.running = true; }

    property Connections queryChanges: Connections {
        target: root.nState
        function onShortcutQueryChanged(): void { root.query = root.nState.shortcutQuery; }
    }

    property Process builtinListProcess: Process {
        id: builtinListProc
        command: ["python3", `${Paths.home}/.config/quickshell/caelestia/utils/builtin_shortcuts.py`, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.builtinShortcuts = JSON.parse(text); }
                catch (error) { root.builtinError = qsTr("Could not load active shortcuts. Reopen this page to retry."); }
            }
        }
    }

    property Process builtinActionProcess: Process {
        id: builtinAction
        stderr: StdioCollector { id: builtinActionError }
        onExited: code => {
            root.builtinSaving = false;
            if (code === 0) {
                root.selectedBuiltin = null;
                root.recordingShortcut = false;
                builtinListProc.running = true;
                Toaster.toast(qsTr("Shortcut saved"), qsTr("The new key combination is active"), "keyboard");
            } else {
                root.builtinError = builtinActionError.text.trim() || qsTr("Could not save the shortcut");
            }
        }
    }

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
                root.showEditor = false;
                root.refreshCustom();
                builtinListProc.running = true;
            } else {
                Toaster.toast(qsTr("Shortcut error"), customError.text.trim() || qsTr("Could not save the shortcut"), "error");
            }
        }
    }

    property Shortcut findShortcut: Shortcut {
        sequences: [StandardKey.Find]
        enabled: !root.recordingShortcut
        onActivated: {
            root.flickable.contentY = -root.flickable.topMargin;
            searchField.forceActiveFocus();
            searchField.selectAll();
        }
    }

    property ShortcutInhibitor recorderInhibitor: ShortcutInhibitor {
        window: root.QsWindow.window
        enabled: (root.recordingShortcut || root.recorderReleasePending) && builtinKey.activeFocus
        onCancelled: { root.recordingShortcut = false; root.recorderReleasePending = false; }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledTextField {
                id: searchField
                objectName: "shortcutSearch"
                Layout.fillWidth: true
                placeholderText: qsTr("Search actions, keys or categories")
                leadingIcon: "search"
                supportingText: qsTr('Try: pencereyi küçült, başka masaüstüne taşı, Win+T • Ctrl+F')
                Accessible.name: qsTr("Search shortcuts")
                Keys.onEscapePressed: event => {
                    if (text) {
                        clear();
                        event.accepted = true;
                    } else {
                        event.accepted = false;
                    }
                }
            }
            IconButton {
                visible: root.query.length > 0
                icon: "close"
                type: IconButton.Text
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Clear search")
                Keys.onReturnPressed: clicked()
                Keys.onSpacePressed: clicked()
                onClicked: { searchField.clear(); searchField.forceActiveFocus(); }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.small

            Repeater {
                model: [{ id: "", title: qsTr("All"), icon: "apps" }, ...root.allGroups]

                delegate: TextButton {
                    required property var modelData
                    readonly property int count: root.searchGroups.filter(group => !modelData.id || group.id === modelData.id).reduce((sum, group) => sum + group.entries.length, 0)
                    text: modelData.title + " (" + count + ")"
                    isToggle: true
                    checked: root.category === modelData.id
                    type: TextButton.Tonal
                    activeFocusOnTab: true
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: text
                    Accessible.checked: checked
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                    onClicked: root.category = modelData.id
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            Layout.bottomMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: qsTr("%1 of %2 entries").arg(root.resultCount).arg(root.totalCount)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                Accessible.role: Accessible.StaticText
            }
            TextButton {
                visible: root.query.length > 0 || root.category !== ""
                text: qsTr("Reset filters")
                type: TextButton.Text
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: text
                Keys.onReturnPressed: clicked()
                Keys.onSpacePressed: clicked()
                onClicked: root.resetSearch()
            }
            IconTextButton {
                icon: root.showEditor ? "close" : "add"
                text: qsTr("Custom shortcut")
                type: ButtonBase.Tonal
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: text
                Keys.onReturnPressed: clicked()
                Keys.onSpacePressed: clicked()
                onClicked: {
                    root.showEditor = !root.showEditor;
                    if (root.showEditor) {
                        root.selectedBuiltin = null;
                        root.recordingShortcut = false;
                        Qt.callLater(() => shortcutKey.forceActiveFocus());
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.builtinError !== "" && !root.selectedBuiltin
            text: root.builtinError
            color: Colours.palette.m3error
            wrapMode: Text.WordWrap
        }

        ConnectedRect {
            Layout.fillWidth: true
            visible: root.selectedBuiltin !== null
            first: true
            last: true
            implicitHeight: builtinEditor.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: builtinEditor
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText { text: qsTr("Edit built-in shortcut"); font: Tokens.font.title.medium }
                StyledText {
                    Layout.fillWidth: true
                    text: root.editingBuiltinDescription
                    textFormat: Text.PlainText
                    font: Tokens.font.body.medium
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Choose an alternative below, then type or record a new key combination. The action stays the same.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    Repeater {
                        model: root.editingBindings
                        delegate: TextButton {
                            required property var modelData
                            text: modelData.key
                            isToggle: true
                            checked: root.selectedBuiltin?.original === modelData.original
                            type: TextButton.Tonal
                            disabled: root.builtinSaving
                            activeFocusOnTab: true
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: text
                            Accessible.checked: checked
                            Keys.onReturnPressed: clicked()
                            Keys.onSpacePressed: clicked()
                            onClicked: root.chooseBuiltin(modelData)
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium
                    StyledTextField {
                        id: builtinKey
                        objectName: "builtinShortcutKey"
                        Layout.fillWidth: true
                        placeholderText: root.recordingShortcut ? qsTr("Press the new shortcut…") : qsTr("Key combination")
                        leadingIcon: "keyboard"
                        readOnly: root.recordingShortcut || root.builtinSaving
                        supportingText: root.builtinConflict || root.builtinError || (root.recordingShortcut ? qsTr("Press Escape to cancel recording") : qsTr("Default: %1").arg(root.selectedBuiltin?.original ?? ""))
                        isError: root.builtinConflict !== "" || root.builtinError !== ""
                        errorText: root.builtinConflict || root.builtinError
                        Accessible.name: qsTr("New key combination")
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => root.recordKey(event)
                        Keys.onReleased: event => {
                            if (root.recorderReleasePending) {
                                event.accepted = true;
                                if (event.modifiers === Qt.NoModifier) root.recorderReleasePending = false;
                            }
                        }
                        onActiveFocusChanged: if (!activeFocus) { root.recordingShortcut = false; root.recorderReleasePending = false; }
                    }
                    TextButton {
                        text: root.recordingShortcut ? qsTr("Cancel recording") : qsTr("Record keys")
                        type: TextButton.Tonal
                        disabled: root.builtinSaving
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: text
                        Keys.onReturnPressed: clicked()
                        Keys.onSpacePressed: clicked()
                        onClicked: {
                            root.recordingShortcut = !root.recordingShortcut;
                            if (root.recordingShortcut) {
                                builtinKey.clear();
                                builtinKey.forceActiveFocus();
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium
                    TextButton {
                        text: qsTr("Restore default")
                        type: TextButton.Text
                        disabled: root.builtinSaving || !root.selectedBuiltin?.changed
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: text
                        Keys.onReturnPressed: clicked()
                        Keys.onSpacePressed: clicked()
                        onClicked: root.saveBuiltin(true)
                    }
                    Item { Layout.fillWidth: true }
                    TextButton {
                        text: qsTr("Cancel")
                        type: TextButton.Text
                        disabled: root.builtinSaving
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: text
                        Keys.onReturnPressed: clicked()
                        Keys.onSpacePressed: clicked()
                        onClicked: { root.selectedBuiltin = null; root.recordingShortcut = false; }
                    }
                    IconTextButton {
                        icon: "save"
                        text: root.builtinSaving ? qsTr("Saving…") : qsTr("Save shortcut")
                        type: ButtonBase.Filled
                        disabled: root.builtinSaving || root.recordingShortcut || !builtinKey.text.trim() || root.builtinConflict !== ""
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: text
                        Keys.onReturnPressed: clicked()
                        Keys.onSpacePressed: clicked()
                        onClicked: root.saveBuiltin(false)
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            visible: root.showEditor
            first: true
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
                    TextButton { visible: root.editingId; text: qsTr("Cancel edit"); type: TextButton.Text; onClicked: { root.clearEditor(); root.showEditor = false; } }
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

        Repeater {
            model: root.visibleGroups

            delegate: ColumnLayout {
                id: group
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: group.index === 0
                    text: group.modelData.title + " (" + group.modelData.entries.length + ")"
                }

                Repeater {
                    model: group.modelData.entries

                    delegate: ConnectedRect {
                        id: entryRow
                        required property var modelData
                        required property int index
                        readonly property var custom: modelData[3] || null
                        readonly property var bindings: modelData[4] || []
                        Layout.fillWidth: true
                        first: index === 0
                        last: index === group.modelData.entries.length - 1
                        implicitHeight: entryLayout.implicitHeight + Tokens.padding.medium * 2

                        RowLayout {
                            id: entryLayout
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            anchors.leftMargin: Tokens.padding.largeIncreased
                            anchors.rightMargin: Tokens.padding.largeIncreased
                            spacing: Tokens.spacing.medium

                            MaterialIcon { text: group.modelData.icon; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.small }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: entryRow.modelData[1]
                                    textFormat: Text.PlainText
                                    font: Tokens.font.body.small
                                    wrapMode: Text.WordWrap
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: entryRow.custom !== null
                                    text: entryRow.custom?.command ?? ""
                                    textFormat: Text.PlainText
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                    wrapMode: Text.WrapAnywhere
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: entryRow.bindings.some(binding => binding.changed)
                                    text: qsTr("Modified • Default: %1").arg(entryRow.bindings.filter(binding => binding.changed).map(binding => binding.original).join(" / "))
                                    color: Colours.palette.m3primary
                                    font: Tokens.font.label.small
                                    wrapMode: Text.WordWrap
                                }
                            }
                            StyledText {
                                Layout.maximumWidth: entryRow.width * 0.4
                                text: entryRow.modelData[0]
                                textFormat: Text.PlainText
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignRight
                            }
                            IconButton {
                                visible: entryRow.custom !== null || entryRow.bindings.length > 0
                                icon: "edit"
                                type: IconButton.Text
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Edit %1").arg(entryRow.modelData[1])
                                Keys.onReturnPressed: clicked()
                                Keys.onSpacePressed: clicked()
                                onClicked: {
                                    if (entryRow.custom) root.editCustom(entryRow.custom);
                                    else root.editBuiltin(entryRow.modelData);
                                    root.flickable.contentY = -root.flickable.topMargin;
                                }
                            }
                            IconButton {
                                visible: entryRow.custom !== null
                                icon: "delete"
                                type: IconButton.Text
                                disabled: root.customActionRunning
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Delete %1").arg(entryRow.modelData[1])
                                Keys.onReturnPressed: clicked()
                                Keys.onSpacePressed: clicked()
                                onClicked: root.deleteCustom(entryRow.custom.id)
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large
            visible: root.resultCount === 0
            text: qsTr("No shortcuts found. Try fewer words or choose another category.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
            wrapMode: Text.WordWrap
        }


    }
}
