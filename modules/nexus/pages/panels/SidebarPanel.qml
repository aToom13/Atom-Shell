pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Sidebar")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("General")
        }

        ToggleRow {
            first: true
            text: qsTr("Enabled")
            checked: Config.sidebar.enabled
            onToggled: GlobalConfig.sidebar.enabled = checked
        }

        ToggleRow {
            text: qsTr("Reveal on hover")
            subtext: qsTr("Open the sidebar when the pointer reaches its edge")
            checked: Config.sidebar.showOnHover
            onToggled: GlobalConfig.sidebar.showOnHover = checked
        }

        StepperRow {
            label: qsTr("Hover threshold")
            subtext: qsTr("Minimum edge distance before hover reveal (px)")
            value: Config.sidebar.minHoverThreshold
            from: 0
            to: 400
            stepSize: 5
            onMoved: v => GlobalConfig.sidebar.minHoverThreshold = v
        }

        StepperRow {
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the sidebar opens")
            value: Config.sidebar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.sidebar.dragThreshold = v
        }
    }
}
