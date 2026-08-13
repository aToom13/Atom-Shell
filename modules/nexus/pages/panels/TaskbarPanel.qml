pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    function componentEnabled(componentId: string): bool {
        const entry = Config.bar.entries.values.find(e => e.id === componentId);
        return entry?.enabled ?? true;
    }

    function setComponentEnabled(componentId: string, enabled: bool): void {
        const entries = GlobalConfig.bar.entries;
        for (let i = 0; i < entries.count; i++) {
            const entry = entries.at(i);
            if (entry.id === componentId) {
                entry.enabled = enabled;
                return;
            }
        }
        entries.insert({ id: componentId, enabled });
    }

    function moveComponent(index: int, delta: int): void {
        const target = index + delta;
        if (target < 0 || target >= Config.bar.entries.count)
            return;
        GlobalConfig.bar.entries.move(index, target);
    }

    function componentLabel(id: string): string {
        const labels = { logo: qsTr("Logo"), workspaces: qsTr("Workspaces"), spacer: qsTr("Flexible spacer"), activeWindow: qsTr("Active window"), tray: qsTr("System tray"), clock: qsTr("Clock"), statusIcons: qsTr("Status icons"), power: qsTr("Power button") };
        return labels[id] ?? id;
    }

    function screenBarEnabled(screenName: string): bool {
        return !Strings.testRegexList(GlobalConfig.bar.excludedScreens, screenName);
    }

    function setScreenBarEnabled(screenName: string, enabled: bool): void {
        const current = GlobalConfig.bar.excludedScreens;
        if (enabled)
            GlobalConfig.bar.excludedScreens = current.filter(pattern => !Strings.testRegexList([pattern], screenName));
        else if (!Strings.testRegexList(current, screenName))
            GlobalConfig.bar.excludedScreens = [...current, screenName];
    }

    title: qsTr("Taskbar")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Behaviour
        SectionHeader {
            first: true
            text: qsTr("Behaviour")
        }

        ToggleRow {
            first: true
            text: qsTr("Persistent")
            subtext: qsTr("Keep the bar visible at all times")
            checked: Config.bar.persistent
            onToggled: GlobalConfig.bar.persistent = checked
        }

        ToggleRow {
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal the bar when the cursor reaches the screen edge")
            checked: Config.bar.showOnHover
            onToggled: GlobalConfig.bar.showOnHover = checked
        }

        StepperRow {
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the bar reveals")
            value: Config.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.bar.dragThreshold = v
        }

        // Components
        SectionHeader {
            text: qsTr("Components")
        }

        ToggleRow {
            first: true
            text: qsTr("Logo")
            checked: root.componentEnabled("logo")
            onToggled: root.setComponentEnabled("logo", checked)
        }

        ToggleRow {
            text: qsTr("Workspaces")
            checked: root.componentEnabled("workspaces")
            onToggled: root.setComponentEnabled("workspaces", checked)
        }

        ToggleRow {
            text: qsTr("Active window")
            checked: root.componentEnabled("activeWindow")
            onToggled: root.setComponentEnabled("activeWindow", checked)
        }

        ToggleRow {
            text: qsTr("System tray")
            checked: root.componentEnabled("tray")
            onToggled: root.setComponentEnabled("tray", checked)
        }

        ToggleRow {
            text: qsTr("Clock")
            checked: root.componentEnabled("clock")
            onToggled: root.setComponentEnabled("clock", checked)
        }

        ToggleRow {
            text: qsTr("Status icons")
            checked: root.componentEnabled("statusIcons")
            onToggled: root.setComponentEnabled("statusIcons", checked)
        }

        ToggleRow {
            last: true
            text: qsTr("Power button")
            checked: root.componentEnabled("power")
            onToggled: root.setComponentEnabled("power", checked)
        }

        SectionHeader { text: qsTr("Component order") }

        Repeater {
            model: Config.bar.entries.values
            delegate: ConnectedRect {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: index === Config.bar.entries.count - 1
                implicitHeight: orderLayout.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: orderLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    MaterialIcon { text: "drag_indicator"; color: Colours.palette.m3outline; fontStyle: Tokens.font.icon.small }
                    StyledText { Layout.fillWidth: true; text: root.componentLabel(modelData.id); color: (modelData.enabled ?? true) ? Colours.palette.m3onSurface : Colours.palette.m3outline; font: Tokens.font.body.small }
                    IconButton { icon: "arrow_upward"; type: IconButton.Text; disabled: index === 0; onClicked: root.moveComponent(index, -1) }
                    IconButton { icon: "arrow_downward"; type: IconButton.Text; disabled: index === Config.bar.entries.count - 1; onClicked: root.moveComponent(index, 1) }
                }
            }
        }

        SectionHeader { text: qsTr("Displays") }

        Repeater {
            model: Quickshell.screens
            delegate: ToggleRow {
                required property var modelData
                required property int index
                first: index === 0
                last: index === Quickshell.screens.length - 1
                text: modelData.name
                subtext: qsTr("Show the taskbar on this display")
                checked: root.screenBarEnabled(modelData.name)
                onToggled: root.setScreenBarEnabled(modelData.name, checked)
            }
        }

        SectionHeader {
            text: qsTr("Component settings")
        }

        NavRow {
            first: true
            icon: "workspaces"
            text: qsTr("Workspaces")
            subtext: qsTr("Indicators, window icons")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "web_asset"
            text: qsTr("Active window")
            subtext: qsTr("Title display, popout")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "widgets"
            text: qsTr("Tray")
            subtext: qsTr("System tray icons")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            icon: "signal_cellular_alt"
            text: qsTr("Status icons")
            subtext: qsTr("Visible indicators")
            onClicked: root.nState.openSubPage(9)
        }

        NavRow {
            last: true
            icon: "schedule"
            text: qsTr("Clock")
            subtext: qsTr("Date, icon, background")
            onClicked: root.nState.openSubPage(10)
        }

        // Scroll actions
        SectionHeader {
            text: qsTr("Scroll actions")
        }

        ToggleRow {
            first: true
            text: qsTr("Workspaces")
            subtext: qsTr("Scroll over the workspace indicator to switch workspaces")
            checked: Config.bar.scrollActions.workspaces
            onToggled: GlobalConfig.bar.scrollActions.workspaces = checked
        }

        ToggleRow {
            text: qsTr("Volume")
            subtext: qsTr("Scroll on the top half of the bar to adjust volume")
            checked: Config.bar.scrollActions.volume
            onToggled: GlobalConfig.bar.scrollActions.volume = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Brightness")
            subtext: qsTr("Scroll on the bottom half of the bar to adjust brightness")
            checked: Config.bar.scrollActions.brightness
            onToggled: GlobalConfig.bar.scrollActions.brightness = checked
        }
    }
}
