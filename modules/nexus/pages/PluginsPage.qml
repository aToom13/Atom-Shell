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

    property string hyprPlugins: qsTr("Loading…")
    property string hyprPmStatus: qsTr("Loading…")
    property list<var> repositories: []
    property list<var> managedPlugins: []
    property list<var> loadedPlugins: []
    property bool refreshing
    property bool changingPlugin
    property bool actionRequested
    property string requestedPlugin
    property bool requestedEnabled
    property bool headersReady
    property bool cacheWritable: true
    property string compatibilityStatus: qsTr("Checking plugin ABI…")
    property string actionError
    property string currentAbi
    property string cachedAbi
    property string headerVersion
    property bool managing
    property string managementTitle
    property string managementLog
    property string pendingRemoval
    property string dynamicMode: "tilt"
    property real dynamicThreshold: 2
    property bool dynamicShake
    readonly property bool runtimeReady: headersReady && cacheWritable
    readonly property bool hasDynamicCursors: managedPlugins.some(plugin => plugin.name === "dynamic-cursors")
    readonly property list<MenuItem> dynamicModeItems: [
        MenuItem { text: qsTr("Tilt") },
        MenuItem { text: qsTr("Rotate") },
        MenuItem { text: qsTr("Stretch") },
        MenuItem { text: qsTr("None") }
    ]
    readonly property list<string> dynamicModeValues: ["tilt", "rotate", "stretch", "none"]

    function clean(text: string): string {
        return text.replace(/\x1b\[[0-9;]*m/g, "").trim();
    }

    function parseHyprPm(text: string): void {
        const repos = [];
        const plugins = [];
        let repo = "";
        let author = "";
        let plugin = "";
        for (const line of clean(text).split("\n")) {
            let match = line.match(/Repository\s+(.+?)\s+\(by\s+(.+?)\):/);
            if (match) {
                repo = match[1].trim();
                author = match[2].trim();
                repos.push({ name: repo, author });
                continue;
            }
            match = line.match(/Plugin\s+(.+)$/);
            if (match) {
                plugin = match[1].trim();
                continue;
            }
            match = line.match(/enabled:\s*(true|false)/i);
            if (match && plugin) {
                plugins.push({ repo, author, name: plugin, enabled: match[1].toLowerCase() === "true" });
                plugin = "";
            }
        }
        repositories = repos;
        managedPlugins = plugins;
    }

    function parseLoadedPlugins(text: string): void {
        const plugins = [];
        let current = null;
        for (const line of clean(text).split("\n")) {
            const header = line.match(/^Plugin\s+(.+?)\s+by\s+(.+?):$/);
            if (header) {
                current = { name: header[1], author: header[2], version: "", description: "" };
                plugins.push(current);
                continue;
            }
            if (!current)
                continue;
            const version = line.match(/^\s*Version:\s*(.*)$/);
            const description = line.match(/^\s*Description:\s*(.*)$/);
            if (version) current.version = version[1];
            if (description) current.description = description[1];
        }
        loadedPlugins = plugins;
    }

    function refresh(): void {
        refreshing = true;
        liveProc.running = pmProc.running = compatibilityProc.running = pluginSettingsProc.running = true;
    }

    function setDynamicSetting(key: string, value: var): void {
        if (pluginSettingsAction.running)
            return;
        pluginSettingsAction.command = [`${Paths.home}/.config/hypr/scripts/manage-plugin-settings.sh`, "set", key, String(value)];
        pluginSettingsAction.running = true;
    }

    function finishOne(): void {
        if (!liveProc.running && !pmProc.running && !compatibilityProc.running)
            refreshing = false;
    }

    function appendManagement(line: string): void {
        const cleaned = clean(line);
        if (!cleaned)
            return;
        const lines = `${managementLog}${managementLog ? "\n" : ""}${cleaned}`.split("\n");
        managementLog = lines.slice(Math.max(0, lines.length - 80)).join("\n");
    }

    function runManagement(title: string, command: list<string>): void {
        if (managing || changingPlugin)
            return;
        managementTitle = title;
        managementLog = qsTr("Starting…");
        managing = true;
        managementProc.command = command;
        managementProc.running = true;
    }

    function openPluginUpdater(): void {
        runManagement(qsTr("Repairing plugin runtime"), [`${Paths.home}/.config/hypr/scripts/manage-hyprpm.sh`, "repair"]);
    }

    function enableWithRepair(name: string): void {
        const safeName = name.replace(/'/g, "'\\''");
        runManagement(qsTr("Repairing and enabling %1").arg(name), ["sh", "-c", `${Paths.home}/.config/hypr/scripts/manage-hyprpm.sh repair && hyprpm enable '${safeName}' && hyprpm reload`]);
    }

    function setPlugin(name: string, enabled: bool): void {
        if (changingPlugin)
            return;
        if (enabled && !runtimeReady) {
            enableWithRepair(name);
            return;
        }
        changingPlugin = true;
        actionRequested = true;
        actionError = "";
        requestedPlugin = name;
        requestedEnabled = enabled;
        const action = enabled ? "enable" : "disable";
        const safeName = name.replace(/'/g, "'\\''");
        pluginAction.command = ["sh", "-c", root.headersReady ?
            `hyprpm ${action} '${safeName}' && hyprpm reload` :
            `hyprpm ${action} '${safeName}'`];
        pluginAction.running = true;
    }

    function addRepository(url: string): void {
        const trimmed = url.trim();
        if (!trimmed)
            return;
        runManagement(qsTr("Installing plugin repository"), ["hyprpm", "add", trimmed]);
    }

    function removeRepository(name: string): void {
        pendingRemoval = name;
    }

    function confirmRemoveRepository(): void {
        if (!pendingRemoval)
            return;
        const name = pendingRemoval;
        pendingRemoval = "";
        runManagement(qsTr("Removing %1").arg(name), ["sh", "-c", `hyprpm remove '${name.replace(/'/g, "'\\''")}' && hyprpm reload`]);
    }

    function rebuildRepository(name: string): void {
        runManagement(qsTr("Rebuilding %1").arg(name), ["sh", "-c", `${Paths.home}/.config/hypr/scripts/manage-hyprpm.sh rebuild '${name.replace(/'/g, "'\\''")}' && hyprpm reload`]);
    }

    function loadEnabledPlugins(): void {
        if (changingPlugin)
            return;
        if (!runtimeReady) {
            openPluginUpdater();
            return;
        }
        changingPlugin = true;
        actionRequested = true;
        actionError = "";
        pluginAction.command = ["hyprpm", "reload"];
        pluginAction.running = true;
    }

    title: qsTr("Plugins")
    Component.onCompleted: refresh()

    property Process liveProcess: Process {
        id: liveProc
        command: ["hyprctl", "plugin", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.hyprPlugins = root.clean(text) || qsTr("No plugins loaded");
                root.parseLoadedPlugins(text);
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) root.hyprPlugins = root.clean(text)
        }
        onExited: root.finishOne()
    }

    property Process pmProcess: Process {
        id: pmProc
        command: ["hyprpm", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.hyprPmStatus = root.clean(text) || qsTr("No managed plugins");
                root.parseHyprPm(text);
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) root.hyprPmStatus = root.clean(text)
        }
        onExited: root.finishOne()
    }

    property Process compatibilityProcess: Process {
        id: compatibilityProc
        command: [`${Paths.home}/.config/hypr/scripts/manage-hyprpm.sh`, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const values = {};
                for (const line of text.trim().split("\n")) {
                    const split = line.indexOf("\t");
                    if (split > 0)
                        values[line.slice(0, split)] = line.slice(split + 1);
                }
                root.currentAbi = values.current ?? "";
                root.cachedAbi = values.cached ?? "";
                root.headerVersion = values.headers ?? "";
                root.headersReady = !!root.currentAbi && root.currentAbi === root.cachedAbi;
                root.cacheWritable = values.writable !== "no";
                root.compatibilityStatus = !root.cacheWritable ? qsTr("HyprPM cache is owned by root and is not writable") : root.headersReady ? qsTr("Plugin headers match the running Hyprland") : qsTr("Headers are outdated for this Hyprland version")
            }
        }
        onExited: root.finishOne()
    }

    property Process managementProcess: Process {
        id: managementProc
        stdout: SplitParser { onRead: data => root.appendManagement(data) }
        stderr: SplitParser { onRead: data => root.appendManagement(data) }
        onExited: code => {
            root.managing = false;
            root.appendManagement(code === 0 ? qsTr("Completed successfully.") : qsTr("Failed with exit code %1.").arg(code));
            Toaster.toast(code === 0 ? qsTr("Plugin operation completed") : qsTr("Plugin operation failed"), root.managementTitle, code === 0 ? "extension" : "error");
            root.refresh();
        }
    }

    property Process pluginSettingsProcess: Process {
        id: pluginSettingsProc
        command: [`${Paths.home}/.config/hypr/scripts/manage-plugin-settings.sh`, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const values = text.trim().split("\t");
                root.dynamicMode = values[0] || "tilt";
                root.dynamicThreshold = Number(values[1] || 2);
                root.dynamicShake = values[2] === "true";
            }
        }
    }

    property Process pluginSettingsActionProcess: Process {
        id: pluginSettingsAction
        stderr: StdioCollector { id: pluginSettingsError }
        onExited: code => {
            if (code !== 0)
                Toaster.toast(qsTr("Plugin setting error"), pluginSettingsError.text.trim() || qsTr("Could not apply the setting"), "error");
            pluginSettingsProc.running = true;
        }
    }

    property Process pluginActionProcess: Process {
        id: pluginAction
        stderr: StdioCollector {
            onStreamFinished: root.actionError = root.clean(text)
        }
        onExited: code => {
            if (!root.actionRequested)
                return;
            root.actionRequested = false;
            root.changingPlugin = false;
            if (code === 0)
                Toaster.toast(qsTr("Plugin changed"), root.headersReady ? qsTr("%1 is now %2").arg(root.requestedPlugin).arg(root.requestedEnabled ? qsTr("enabled") : qsTr("disabled")) : qsTr("%1 was %2; repair the runtime to load it").arg(root.requestedPlugin).arg(root.requestedEnabled ? qsTr("enabled") : qsTr("disabled")), "extension");
            else
                Toaster.toast(qsTr("Plugin error"), root.actionError || qsTr("Could not change %1").arg(root.requestedPlugin), "error");
            root.refresh();
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Timer {
            running: root.visible
            repeat: true
            interval: 5000
            onTriggered: {
                if (!root.refreshing && !root.changingPlugin)
                    root.refresh();
            }
        }

        SectionHeader { first: true; text: qsTr("Plugin runtime") }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: repairLayout.implicitHeight + Tokens.padding.large * 2
            color: Colours.layer(root.runtimeReady ? Colours.palette.m3primaryContainer : Colours.palette.m3errorContainer, 2)

            RowLayout {
                id: repairLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium
                MaterialIcon { text: root.runtimeReady ? "verified" : "build_circle"; color: root.runtimeReady ? Colours.palette.m3primary : Colours.palette.m3error; fontStyle: Tokens.font.icon.medium }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { Layout.fillWidth: true; text: root.runtimeReady ? qsTr("Plugin runtime is ready") : qsTr("Plugin runtime needs repair"); font: Tokens.font.body.medium }
                    StyledText { Layout.fillWidth: true; text: root.compatibilityStatus; color: Colours.palette.m3outline; font: Tokens.font.label.small; wrapMode: Text.WordWrap }
                }
                IconTextButton {
                    icon: root.managing ? "sync" : root.runtimeReady ? "system_update_alt" : "build"
                    text: root.managing ? qsTr("Working…") : root.runtimeReady ? qsTr("Rebuild all") : qsTr("Repair & load")
                    type: ButtonBase.Filled
                    disabled: root.managing || root.changingPlugin
                    onClicked: root.openPluginUpdater()
                }
            }
        }

        InfoRow { Layout.topMargin: Tokens.spacing.extraSmall; first: true; icon: "deployed_code"; label: qsTr("Installed headers"); value: root.headerVersion || qsTr("Unknown") }
        InfoRow { last: true; icon: "fingerprint"; label: qsTr("Running ABI"); value: root.currentAbi ? root.currentAbi.slice(0, 12) : qsTr("Unknown") }

        SectionHeader { visible: root.managementLog; text: root.managementTitle || qsTr("Plugin operation") }
        ConnectedRect {
            visible: root.managementLog
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: Math.min(managementText.implicitHeight, 260) + Tokens.padding.large * 2
            StyledText {
                id: managementText
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                text: root.managementLog
                wrapMode: Text.WrapAnywhere
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.mono.small
                elide: Text.ElideLeft
                maximumLineCount: 18
            }
        }

        SectionHeader { text: qsTr("Loaded in Hyprland") }
        InfoRow {
            visible: root.loadedPlugins.length === 0
            first: true
            last: true
            icon: "extension_off"
            label: qsTr("No plugins loaded")
            value: ""
        }
        Repeater {
            model: root.loadedPlugins
            delegate: InfoRow {
                required property var modelData
                required property int index
                first: index === 0
                last: index === root.loadedPlugins.length - 1
                icon: "extension"
                label: modelData.name
                subtext: modelData.description
                value: modelData.version ? qsTr("v%1").arg(modelData.version) : modelData.author
            }
        }

        SectionHeader { text: qsTr("Managed plugins") }

        InfoRow {
            visible: root.managedPlugins.length === 0
            first: true
            last: true
            icon: "extension_off"
            label: qsTr("No managed plugins")
            subtext: qsTr("Add a repository below to install plugins")
            value: ""
        }

        Repeater {
            model: root.managedPlugins
            delegate: ToggleRow {
                required property var modelData
                required property int index
                first: index === 0
                last: index === root.managedPlugins.length - 1
                text: modelData.name
                subtext: qsTr("%1 • repository: %2").arg(modelData.author).arg(modelData.repo)
                checked: modelData.enabled
                enabled: !root.changingPlugin
                onToggled: root.setPlugin(modelData.name, checked)
            }
        }

        SectionHeader { text: qsTr("Repositories") }

        Repeater {
            model: root.repositories
            delegate: ConnectedRect {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: index === root.repositories.length - 1
                implicitHeight: repoLayout.implicitHeight + Tokens.padding.medium * 2
                RowLayout {
                    id: repoLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    MaterialIcon { text: "source"; fontStyle: Tokens.font.icon.medium }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { text: modelData.name; font: Tokens.font.body.small }
                        StyledText { text: qsTr("Maintained by %1").arg(modelData.author); color: Colours.palette.m3outline; font: Tokens.font.label.small }
                    }
                    IconButton { icon: "build"; type: IconButton.Text; disabled: root.managing; onClicked: root.rebuildRepository(modelData.name) }
                    IconButton { icon: "delete"; type: IconButton.Text; onClicked: root.removeRepository(modelData.name) }
                }
            }
        }

        ConnectedRect {
            visible: root.pendingRemoval
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: removeLayout.implicitHeight + Tokens.padding.large * 2
            color: Colours.layer(Colours.palette.m3errorContainer, 2)
            RowLayout {
                id: removeLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium
                MaterialIcon { text: "warning"; color: Colours.palette.m3error; fontStyle: Tokens.font.icon.medium }
                StyledText { Layout.fillWidth: true; text: qsTr("Remove %1 and all of its plugins?").arg(root.pendingRemoval); wrapMode: Text.WordWrap; font: Tokens.font.body.small }
                TextButton { text: qsTr("Cancel"); type: TextButton.Text; onClicked: root.pendingRemoval = "" }
                IconTextButton { icon: "delete"; text: qsTr("Remove"); type: ButtonBase.Filled; onClicked: root.confirmRemoveRepository() }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: root.repositories.length === 0
            last: true
            implicitHeight: addRepoLayout.implicitHeight + Tokens.padding.medium * 2
            RowLayout {
                id: addRepoLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium
                StyledTextField {
                    id: repositoryUrl
                    Layout.fillWidth: true
                    placeholderText: qsTr("Git repository URL")
                    leadingIcon: "link"
                    supportingText: qsTr("HyprPM plugin repository")
                    onAccepted: root.addRepository(text)
                }
                IconTextButton { icon: "add"; text: qsTr("Add"); type: ButtonBase.Filled; disabled: !repositoryUrl.text.trim(); onClicked: root.addRepository(repositoryUrl.text) }
            }
        }

        SectionHeader { visible: root.hasDynamicCursors; text: qsTr("Dynamic Cursors") }
        SelectRow {
            visible: root.hasDynamicCursors
            first: true
            label: qsTr("Cursor motion")
            subtext: qsTr("Simulation used while the pointer moves")
            menuItems: root.dynamicModeItems
            active: root.dynamicModeItems[Math.max(0, root.dynamicModeValues.indexOf(root.dynamicMode))]
            onSelected: item => root.setDynamicSetting("mode", root.dynamicModeValues[root.dynamicModeItems.indexOf(item)])
        }
        StepperRow {
            visible: root.hasDynamicCursors
            label: qsTr("Shape threshold")
            subtext: qsTr("Lower is smoother but updates the hardware cursor more often")
            value: root.dynamicThreshold
            from: 1
            to: 20
            stepSize: 1
            onMoved: value => root.setDynamicSetting("threshold", value)
        }
        ToggleRow {
            visible: root.hasDynamicCursors
            last: true
            text: qsTr("Shake to find")
            subtext: qsTr("Magnify the pointer when it is shaken")
            checked: root.dynamicShake
            onToggled: root.setDynamicSetting("shakeEnabled", checked)
        }
        RowLayout {
            visible: root.hasDynamicCursors
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.medium
            IconTextButton {
                icon: "search"
                text: qsTr("Test magnification")
                type: IconTextButton.Tonal
                onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "plugin:dynamic-cursors:magnify", "1500 4"])
            }
            IconTextButton {
                icon: "edit_note"
                text: qsTr("Advanced settings")
                type: ButtonBase.Filled
                onClicked: Quickshell.execDetached(["sh", "-c", `"${Quickshell.env("EDITOR") || "codium"}" "${Paths.config}/hypr-user.lua"`])
            }
        }

        SectionHeader { text: qsTr("Plugin configuration") }
        NavRow {
            first: true
            icon: "edit_note"
            text: qsTr("Edit plugin settings")
            subtext: qsTr("Open the Lua configuration used by Hyprland")
            onClicked: Quickshell.execDetached(["sh", "-c", `"${Quickshell.env("EDITOR") || "codium"}" "${Paths.config}/hypr-user.lua"`])
        }
        NavRow {
            last: true
            icon: "folder_open"
            text: qsTr("Open plugin directory")
            subtext: qsTr("Inspect sources and build files managed by HyprPM")
            onClicked: Quickshell.execDetached(["sh", "-c", "xdg-open /var/cache/hyprpm/$(id -un)"])
        }

        SectionHeader { text: qsTr("Shell components") }
        InfoRow { first: true; icon: "widgets"; label: "Atom Shell"; value: qsTr("Active") }
        InfoRow { icon: "dashboard_customize"; label: "Quickshell"; value: qsTr("Active") }
        InfoRow { last: true; icon: "view_quilt"; label: "qs-hyprview"; value: qsTr("Configured") }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.large
            spacing: Tokens.spacing.medium
            IconTextButton {
                icon: "refresh"
                text: qsTr("Refresh")
                type: IconTextButton.Tonal
                disabled: root.refreshing || root.managing
                onClicked: root.refresh()
            }
            IconTextButton {
                icon: "play_arrow"
                text: root.runtimeReady ? qsTr("Load enabled") : qsTr("Repair & load")
                type: IconTextButton.Tonal
                disabled: root.changingPlugin || root.managing
                onClicked: root.runtimeReady ? root.loadEnabledPlugins() : root.openPluginUpdater()
            }
            IconTextButton {
                icon: "extension"
                text: qsTr("Update plugins")
                type: ButtonBase.Filled
                disabled: root.managing || root.changingPlugin
                onClicked: root.openPluginUpdater()
            }
        }
    }
}
