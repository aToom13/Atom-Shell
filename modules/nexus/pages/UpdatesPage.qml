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
import qs.modules.nexus.common

PageBase {
    id: root

    property list<var> updates: []
    property string query
    property string sourceFilter: "all"
    property bool checking
    property bool snapAvailable
    property string lastChecked: qsTr("Not checked yet")

    readonly property list<var> visibleUpdates: updates.filter(update => {
        const sourceMatches = sourceFilter === "all" || update.source === sourceFilter;
        const q = query.trim().toLowerCase();
        return sourceMatches && (!q || `${update.name} ${update.id} ${update.current} ${update.next} ${update.source}`.toLowerCase().includes(q));
    })
    readonly property list<var> selectedUpdates: updates.filter(update => update.selected)
    readonly property int repoUpdates: updates.filter(update => update.source === "repo").length
    readonly property int aurUpdates: updates.filter(update => update.source === "aur").length
    readonly property int flatpakUpdates: updates.filter(update => update.source === "flatpak").length
    readonly property int snapUpdates: updates.filter(update => update.source === "snap").length

    function shellQuote(value: string): string {
        return "'" + value.replace(/'/g, "'\\''") + "'";
    }

    function parseArch(text: string, source: string): list<var> {
        return text.trim().split("\n").filter(line => line).map(line => {
            const match = line.match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/);
            return match ? { source, id: match[1], name: match[1], current: match[2], next: match[3], selected: true } : null;
        }).filter(item => item);
    }

    function parseFlatpak(text: string): list<var> {
        return text.trim().split("\n").filter(line => line).map(line => {
            const fields = line.split("\t");
            return { source: "flatpak", id: fields[0] ?? "", name: fields[1] || fields[0] || qsTr("Unknown"), current: "", next: fields[2] || fields[3] || "", selected: true };
        }).filter(item => item.id);
    }

    function parseSnap(text: string): list<var> {
        const lines = text.trim().split("\n").filter(line => line);
        if (lines.length < 2)
            return [];
        return lines.slice(1).map(line => {
            const fields = line.trim().split(/\s{2,}/);
            return { source: "snap", id: fields[0] ?? "", name: fields[0] ?? "", current: fields[2] || "", next: fields[1] || "", selected: true };
        }).filter(item => item.id);
    }

    function replaceSource(source: string, incoming: list<var>): void {
        const previous = new Map(updates.filter(item => item.source === source).map(item => [item.id, item.selected]));
        const merged = incoming.map(item => ({
            source: item.source,
            id: item.id,
            name: item.name,
            current: item.current,
            next: item.next,
            selected: previous.has(item.id) ? previous.get(item.id) : true
        }));
        updates = [...updates.filter(item => item.source !== source), ...merged];
    }

    function refresh(): void {
        if (checking)
            return;
        checking = true;
        repoProc.running = aurProc.running = flatpakProc.running = snapProc.running = true;
    }

    function finishOne(): void {
        if (!repoProc.running && !aurProc.running && !flatpakProc.running && !snapProc.running) {
            checking = false;
            lastChecked = Qt.formatDateTime(new Date(), "dd MMM, HH:mm");
        }
    }

    function setSelected(source: string, id: string, selected: bool): void {
        updates = updates.map(item => ({
            source: item.source,
            id: item.id,
            name: item.name,
            current: item.current,
            next: item.next,
            selected: item.source === source && item.id === id ? selected : item.selected
        }));
    }

    function selectVisible(selected: bool): void {
        const keys = new Set(visibleUpdates.map(item => `${item.source}\u0000${item.id}`));
        updates = updates.map(item => ({
            source: item.source,
            id: item.id,
            name: item.name,
            current: item.current,
            next: item.next,
            selected: keys.has(`${item.source}\u0000${item.id}`) ? selected : item.selected
        }));
    }

    function sourceLabel(source: string): string {
        if (source === "repo") return qsTr("Official");
        if (source === "aur") return "AUR";
        if (source === "flatpak") return "Flatpak";
        return "Snap";
    }

    function sourceIcon(source: string): string {
        if (source === "repo") return "inventory_2";
        if (source === "aur") return "deployed_code";
        if (source === "flatpak") return "package_2";
        return "deployed_code_account";
    }

    function updateSelected(): void {
        if (selectedUpdates.length === 0) {
            Toaster.toast(qsTr("No packages selected"), qsTr("Select at least one update first"), "info");
            return;
        }

        const arch = selectedUpdates.filter(item => item.source === "repo" || item.source === "aur").map(item => shellQuote(item.id));
        const flatpak = selectedUpdates.filter(item => item.source === "flatpak").map(item => shellQuote(item.id));
        const snap = selectedUpdates.filter(item => item.source === "snap").map(item => shellQuote(item.id));
        const commands = [];
        if (arch.length) commands.push(`paru -S --needed ${arch.join(" ")}`);
        if (flatpak.length) commands.push(`flatpak update ${flatpak.join(" ")}`);
        if (snap.length) commands.push(`sudo snap refresh ${snap.join(" ")}`);
        const body = commands.join(" && ");
        Quickshell.execDetached(["kitty", "--title", qsTr("Selected Updates"), "-e", "bash", "-lc",
            `${body}; code=$?; echo; if [ $code -eq 0 ]; then echo 'Selected updates completed.'; else echo \"Update exited with code $code.\"; fi; echo 'Press Enter to close.'; read -r`]);
    }

    title: qsTr("Updates")
    Component.onCompleted: refresh()

    property Process repoProcess: Process {
        id: repoProc
        command: ["checkupdates"]
        stdout: StdioCollector { onStreamFinished: root.replaceSource("repo", root.parseArch(text, "repo")) }
        onExited: root.finishOne()
    }

    property Process aurProcess: Process {
        id: aurProc
        command: ["paru", "-Qua"]
        stdout: StdioCollector { onStreamFinished: root.replaceSource("aur", root.parseArch(text, "aur")) }
        onExited: root.finishOne()
    }

    property Process flatpakProcess: Process {
        id: flatpakProc
        command: ["sh", "-c", "command -v flatpak >/dev/null && flatpak remote-ls --updates --columns=application,name,version,branch 2>/dev/null || true"]
        stdout: StdioCollector { onStreamFinished: root.replaceSource("flatpak", root.parseFlatpak(text)) }
        onExited: root.finishOne()
    }

    property Process snapProcess: Process {
        id: snapProc
        command: ["sh", "-c", "if command -v snap >/dev/null; then printf '__AVAILABLE__\\n'; snap refresh --list 2>/dev/null || true; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.snapAvailable = text.startsWith("__AVAILABLE__\n");
                root.replaceSource("snap", root.parseSnap(root.snapAvailable ? text.slice("__AVAILABLE__\n".length) : ""));
            }
        }
        onExited: root.finishOne()
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: summary.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: summary
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large

                MaterialIcon {
                    text: root.checking ? "sync" : root.updates.length > 0 ? "system_update" : "verified"
                    color: root.updates.length > 0 ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.extraLarge
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { text: root.checking ? qsTr("Checking for updates…") : root.updates.length ? qsTr("%1 updates available").arg(root.updates.length) : qsTr("System is up to date"); font: Tokens.font.title.medium }
                    StyledText { text: qsTr("%1 selected • Last checked: %2").arg(root.selectedUpdates.length).arg(root.lastChecked); color: Colours.palette.m3outline; font: Tokens.font.body.small }
                }
                IconButton { icon: "refresh"; type: IconButton.Text; disabled: root.checking; onClicked: root.refresh() }
            }
        }

        StyledTextField {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large
            placeholderText: qsTr("Search packages")
            leadingIcon: "search"
            trailingIcon: text ? "close" : ""
            onTextChanged: root.query = text
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            FilterButton { source: "all"; label: qsTr("All"); iconName: "apps" }
            FilterButton { source: "repo"; label: qsTr("Official (%1)").arg(root.repoUpdates); iconName: "inventory_2" }
            FilterButton { source: "aur"; label: "AUR (%1)".arg(root.aurUpdates); iconName: "deployed_code" }
            FilterButton { source: "flatpak"; label: "Flatpak (%1)".arg(root.flatpakUpdates); iconName: "package_2" }
            FilterButton { visible: root.snapAvailable; source: "snap"; label: "Snap (%1)".arg(root.snapUpdates); iconName: "deployed_code_account" }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            spacing: Tokens.spacing.medium
            StyledText { Layout.fillWidth: true; text: qsTr("%1 packages shown").arg(root.visibleUpdates.length); color: Colours.palette.m3outline; font: Tokens.font.body.small }
            TextButton { text: qsTr("Select shown"); type: TextButton.Text; onClicked: root.selectVisible(true) }
            TextButton { text: qsTr("Clear shown"); type: TextButton.Text; onClicked: root.selectVisible(false) }
        }

        Repeater {
            model: root.visibleUpdates

            delegate: ConnectedRect {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                last: index === root.visibleUpdates.length - 1
                implicitHeight: packageLayout.implicitHeight + Tokens.padding.medium * 2

                StateLayer { onClicked: root.setSelected(modelData.source, modelData.id, !modelData.selected) }

                RowLayout {
                    id: packageLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon { text: modelData.selected ? "check_box" : "check_box_outline_blank"; color: modelData.selected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.medium }
                    MaterialIcon { text: root.sourceIcon(modelData.source); color: Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.small }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: modelData.name; font: Tokens.font.body.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; text: modelData.id === modelData.name ? root.sourceLabel(modelData.source) : `${root.sourceLabel(modelData.source)} • ${modelData.id}`; color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideRight }
                    }
                    StyledText { text: modelData.current && modelData.next ? `${modelData.current}  →  ${modelData.next}` : modelData.next; color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.label.small }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.checking && root.visibleUpdates.length === 0
            Layout.topMargin: Tokens.spacing.large
            text: root.updates.length === 0 ? qsTr("No updates available") : qsTr("No packages match the current filter")
            horizontalAlignment: Text.AlignHCenter
            color: Colours.palette.m3outline
            font: Tokens.font.body.medium
        }

        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.large
            icon: "system_update_alt"
            text: qsTr("Update selected (%1)").arg(root.selectedUpdates.length)
            type: ButtonBase.Filled
            disabled: root.selectedUpdates.length === 0
            onClicked: root.updateSelected()
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            text: qsTr("Package changes and privilege prompts open in a terminal and always require your confirmation.")
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
        }
    }

    component FilterButton: IconTextButton {
        required property string source
        required property string label
        required property string iconName

        Layout.fillWidth: true
        icon: iconName
        text: label
        type: root.sourceFilter === source ? ButtonBase.Filled : IconTextButton.Tonal
        onClicked: root.sourceFilter = source
    }
}
