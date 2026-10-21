pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.launcher.items
import qs.modules.launcher.services
import qs.modules.nexus
import "../../utils/ShortcutSearch.js" as ShortcutSearch

StyledListView {
    id: root

    required property SearchBar search
    required property ScreenState screenState

    property string displayText
    property string openFolderId
    property var shortcutBindings: []
    property var customShortcuts: []
    readonly property var shortcutGroups: [...ShortcutSearch.catalog().map(group => ShortcutSearch.withBindings(group, shortcutBindings)), {
        id: "custom", title: qsTr("Custom shortcuts"), icon: "person", keywords: "ozel kisisel custom command komut",
        entries: customShortcuts.map(item => [item.key, item.description, [item.command]])
    }]

    function shortcutResults(text: string): var {
        const query = text.slice(`${GlobalConfig.launcher.actionPrefix}shortcuts`.length).trim();
        return ShortcutSearch.filterGroups(shortcutGroups, query, "").reduce((results, group) => results.concat(group.entries.map(entry => ({
            name: entry[0], desc: `${group.title} · ${entry[1]}`, icon: group.icon,
            onClicked: list => {
                list.screenState.launcher = false;
                WindowFactory.create(null, { initialPage: PageRegistry.shortcutsPageIndex, initialShortcutQuery: query });
            }
        }))), []);
    }

    property Process shortcutListProcess: Process {
        command: ["python3", `${Paths.home}/.config/quickshell/caelestia/utils/builtin_shortcuts.py`, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.shortcutBindings = JSON.parse(text); }
                catch (error) { console.warn("Could not load active launcher shortcuts:", error); }
            }
        }
    }

    property Process customShortcutListProcess: Process {
        command: [`${Paths.home}/.config/hypr/scripts/manage-shortcut.sh`, "list"]
        stdout: StdioCollector {
            onStreamFinished: root.customShortcuts = text.trim().split("\n").filter(line => line).map(line => {
                const fields = line.split("\t");
                return { key: fields[1] ?? "", description: fields[2] ?? "", command: fields[3] ?? "" };
            })
        }
    }

    readonly property string requestedState: stateForText(search.text)
    readonly property string displayState: stateForText(displayText)

    function syncDisplayText(): void {
        if (screenState.launcher && requestedState === displayState)
            displayText = search.text;
    }

    function stateForText(text: string): string {
        const prefix = GlobalConfig.launcher.actionPrefix;
        if (text.startsWith(prefix)) {
            for (const action of ["calc", "scheme", "variant", "shortcuts"])
                if (text.startsWith(`${prefix}${action} `) || action === "shortcuts" && text === `${prefix}${action}`)
                    return action;

            return "actions";
        }

        return "apps";
    }

    function resultsForText(text: string): var {
        switch (stateForText(text)) {
        case "actions":
            return Actions.query(text);
        case "calc":
            return [0];
        case "scheme":
            return Schemes.query(text);
        case "variant":
            return M3Variants.query(text);
        case "shortcuts":
            return shortcutResults(text);
        default:
            return groupedApps(text);
        }
    }

    function groupedApps(text: string): var {
        if (text.startsWith(GlobalConfig.launcher.specialPrefix))
            return Apps.search(text);

        const allApps = DesktopEntries.applications.values.filter(app => !Strings.testRegexList(GlobalConfig.launcher.hiddenApps, app.id));
        const folders = LauncherFolders.folders.map(folder => {
            const apps = allApps.filter(app => folder.apps.includes(app.id));
            return {
                isFolder: true,
                id: folder.id,
                name: folder.name,
                icon: folder.icon,
                comment: qsTr("%1 applications").arg(apps.length),
                apps
            };
        }).filter(folder => folder.apps.length);
        const query = text.trim().toLowerCase();
        const matchingFolders = folders.filter(folder => !query || `${folder.name} ${folder.apps.map(app => `${app.name} ${app.id}`).join(" ")}`.toLowerCase().includes(query));
        const folderForApp = {};
        for (const folder of matchingFolders)
            for (const app of folder.apps)
                if (!folderForApp[app.id])
                    folderForApp[app.id] = folder;

        const results = [];
        const emittedFolders = new Set();

        for (const app of Apps.search(text)) {
            const folder = folderForApp[app.id];
            if (!folder) {
                results.push(app);
                continue;
            }
            if (emittedFolders.has(folder.id))
                continue;

            emittedFolders.add(folder.id);
            results.push(folder);
            if (folder.id === openFolderId)
                results.push(...folder.apps);
        }

        for (const folder of matchingFolders)
            if (!emittedFolders.has(folder.id))
                results.push(folder);

        return results;
    }

    function toggleFolder(id: string): void {
        openFolderId = openFolderId === id ? "" : id;
    }

    model: ScriptModel {
        values: root.resultsForText(root.displayText)
        onValuesChanged: root.currentIndex = 0
    }

    spacing: Tokens.spacing.small
    orientation: Qt.Vertical
    implicitHeight: (Tokens.sizes.launcher.itemHeight + spacing) * Math.min(Config.launcher.maxShown, count) - spacing

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: ListView.ApplyRange

    highlightFollowsCurrentItem: false
    highlight: StyledRect {
        radius: Tokens.rounding.large
        color: Colours.palette.m3onSurface
        opacity: 0.08

        y: root.currentItem?.y ?? 0
        implicitWidth: root.width
        implicitHeight: root.currentItem?.implicitHeight ?? 0

        Behavior on y {
            Anim {}
        }
    }

    state: screenState.launcher ? requestedState : displayState

    onStateChanged: {
        if (state === "scheme" || state === "variant")
            Schemes.reload();
        else if (state === "shortcuts") {
            shortcutListProcess.running = true;
            customShortcutListProcess.running = true;
        }
    }

    Component.onCompleted: displayText = search.text

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.delegate: appItem
            }
        },
        State {
            name: "actions"

            PropertyChanges {
                root.delegate: actionItem
            }
        },
        State {
            name: "shortcuts"

            PropertyChanges {
                root.delegate: actionItem
            }
        },
        State {
            name: "calc"

            PropertyChanges {
                root.delegate: calcItem
            }
        },
        State {
            name: "scheme"

            PropertyChanges {
                root.delegate: schemeItem
            }
        },
        State {
            name: "variant"

            PropertyChanges {
                root.delegate: variantItem
            }
        }
    ]

    transitions: Transition {
        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 1
                    to: 0.9
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
            }
            PropertyAction {
                target: root
                property: "delegate"
                value: null
            }
            ScriptAction {
                script: root.displayText = root.search.text
            }
            PropertyAction {
                target: root
                property: "delegate"
            }
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 0.9
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
            }
            PropertyAction {
                targets: [root.add, root.remove]
                property: "enabled"
                value: true
            }
        }
    }

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    add: Transition {
        enabled: !root.state

        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            from: 0
            to: 1
        }
    }

    remove: Transition {
        enabled: !root.state

        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            from: 1
            to: 0
        }
    }

    move: Transition {
        Anim {
            property: "y"
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    addDisplaced: Transition {
        Anim {
            property: "y"
            type: Anim.StandardSmall
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    displaced: Transition {
        Anim {
            property: "y"
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    Component {
        id: appItem

        AppItem {
            list: root
            screenState: root.screenState
        }
    }

    Component {
        id: actionItem

        ActionItem {
            list: root
        }
    }

    Component {
        id: calcItem

        CalcItem {
            list: root
        }
    }

    Component {
        id: schemeItem

        SchemeItem {
            list: root
        }
    }

    Component {
        id: variantItem

        VariantItem {
            list: root
        }
    }

    Connections {
        function onTextChanged() {
            root.openFolderId = "";
            root.syncDisplayText();
        }

        target: root.search
    }

    Connections {
        function onLauncherChanged() {
            root.syncDisplayText();
        }

        target: root.screenState
    }
}
