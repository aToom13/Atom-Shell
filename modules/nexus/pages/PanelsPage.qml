import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Panels")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Shell visibility")
        }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Show over fullscreen apps")
            subtext: qsTr("Allow panels and overlays to appear above fullscreen windows")
            checked: Config.general.showOverFullscreen
            onToggled: GlobalConfig.general.showOverFullscreen = checked
        }

        SectionHeader { text: qsTr("Panel geometry") }

        StepperRow {
            first: true
            label: qsTr("Edge thickness")
            subtext: qsTr("Reserved screen-edge area (px)")
            value: Config.border.thickness
            from: Config.border.minThickness
            to: 40
            stepSize: 1
            onMoved: v => GlobalConfig.border.thickness = Math.round(v)
        }

        StepperRow {
            label: qsTr("Outer rounding")
            value: Config.border.rounding
            from: 0
            to: 80
            stepSize: 1
            onMoved: v => GlobalConfig.border.rounding = Math.round(v)
        }

        StepperRow {
            last: true
            label: qsTr("Shape smoothing")
            value: Config.border.smoothing
            from: 0
            to: 80
            stepSize: 1
            onMoved: v => GlobalConfig.border.smoothing = Math.round(v)
        }

        SectionHeader { text: qsTr("Panels") }

        NavRow {
            first: true
            icon: "dashboard"
            text: qsTr("Dashboard")
            subtext: Config.dashboard.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(1)
        }

        NavRow {
            icon: "dock_to_bottom"
            text: qsTr("Taskbar")
            subtext: Config.bar.persistent ? qsTr("Always visible") : Config.bar.showOnHover ? qsTr("Reveal on hover") : qsTr("Reveal on drag")
            onClicked: root.nState.openSubPage(2)
        }

        NavRow {
            icon: "apps"
            text: qsTr("Launcher")
            subtext: Config.launcher.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(3)
        }

        NavRow {
            icon: "dock_to_right"
            text: qsTr("Sidebar")
            subtext: Config.sidebar.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(4)
        }

        NavRow {
            last: true
            icon: "construction"
            text: qsTr("Utilities")
            subtext: Config.utilities.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(5)
        }
    }
}
