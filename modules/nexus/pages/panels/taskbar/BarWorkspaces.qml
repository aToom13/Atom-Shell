pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> capitalisationItems: [
        MenuItem { text: qsTr("Preserve") }, MenuItem { text: qsTr("Uppercase") }, MenuItem { text: qsTr("Lowercase") }
    ]
    readonly property list<string> capitalisationValues: ["preserve", "upper", "lower"]

    title: qsTr("Workspaces")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StepperRow {
            first: true
            label: qsTr("Shown")
            subtext: qsTr("Number of workspaces displayed")
            value: Config.bar.workspaces.shown
            from: 1
            to: 20
            stepSize: 1
            onMoved: v => GlobalConfig.bar.workspaces.shown = v
        }

        ToggleRow {
            text: qsTr("Active indicator")
            checked: Config.bar.workspaces.activeIndicator
            onToggled: GlobalConfig.bar.workspaces.activeIndicator = checked
        }

        ToggleRow {
            text: qsTr("Active trail")
            checked: Config.bar.workspaces.activeTrail
            onToggled: GlobalConfig.bar.workspaces.activeTrail = checked
        }

        ToggleRow {
            text: qsTr("Occupied background")
            checked: Config.bar.workspaces.occupiedBg
            onToggled: GlobalConfig.bar.workspaces.occupiedBg = checked
        }

        ToggleRow {
            text: qsTr("Show windows")
            subtext: qsTr("Show icons of open windows on each workspace")
            checked: Config.bar.workspaces.showWindows
            onToggled: GlobalConfig.bar.workspaces.showWindows = checked
        }

        ToggleRow {
            text: qsTr("Windows on special workspaces")
            checked: Config.bar.workspaces.showWindowsOnSpecialWorkspaces
            onToggled: GlobalConfig.bar.workspaces.showWindowsOnSpecialWorkspaces = checked
        }

        StepperRow {
            label: qsTr("Max window icons")
            value: Config.bar.workspaces.maxWindowIcons
            from: 0
            to: 20
            stepSize: 1
            onMoved: v => GlobalConfig.bar.workspaces.maxWindowIcons = v
        }

        ToggleRow {
            last: true
            text: qsTr("Per-monitor workspaces")
            subtext: qsTr("Show each monitor's workspaces independently")
            checked: GlobalConfig.bar.workspaces.perMonitorWorkspaces
            onToggled: GlobalConfig.bar.workspaces.perMonitorWorkspaces = checked
        }

        SectionHeader { text: qsTr("Labels") }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            implicitHeight: labelLayout.implicitHeight + Tokens.padding.large * 2
            RowLayout {
                id: labelLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium
                StyledTextField { Layout.fillWidth: true; placeholderText: qsTr("Empty workspace"); supportingText: qsTr("Default label"); text: GlobalConfig.bar.workspaces.label; onAccepted: GlobalConfig.bar.workspaces.label = text }
                StyledTextField { Layout.fillWidth: true; placeholderText: qsTr("Occupied"); supportingText: qsTr("Occupied workspace label"); text: GlobalConfig.bar.workspaces.occupiedLabel; onAccepted: GlobalConfig.bar.workspaces.occupiedLabel = text }
                StyledTextField { Layout.fillWidth: true; placeholderText: qsTr("Active"); supportingText: qsTr("Active workspace label"); text: GlobalConfig.bar.workspaces.activeLabel; onAccepted: GlobalConfig.bar.workspaces.activeLabel = text }
            }
        }

        SelectRow {
            last: true
            label: qsTr("Capitalisation")
            subtext: qsTr("Applied when the workspace name is shown")
            menuItems: root.capitalisationItems
            active: root.capitalisationItems[Math.max(0, root.capitalisationValues.indexOf(Config.bar.workspaces.capitalisation))]
            onSelected: item => GlobalConfig.bar.workspaces.capitalisation = root.capitalisationValues[root.capitalisationItems.indexOf(item)]
        }
    }
}
