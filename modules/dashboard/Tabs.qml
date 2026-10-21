pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property real nonAnimWidth
    required property ScreenState screenState
    required property var tabs

    readonly property int count: tabRepeater.count
    readonly property Item currentItem: tabRepeater.itemAt(root.screenState.dashboardTab)

    implicitHeight: bar.implicitHeight + bar.anchors.topMargin + indicator.implicitHeight + indicator.anchors.topMargin + separator.implicitHeight
    height: implicitHeight

    RowLayout {
        id: bar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Tokens.sizes.dashboard.tabIndicatorSpacing
        spacing: 0

        Repeater {
            id: tabRepeater
            model: ScriptModel {
                values: root.tabs
            }

            delegate: Item {
                id: tab

                required property var modelData
                required property int index

                readonly property bool current: root.screenState.dashboardTab === index

                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitWidth: mouse.implicitWidth
                implicitHeight: mouse.implicitHeight

                CustomMouseArea {
                    id: mouse

                    anchors.fill: parent

                    function onWheel(event: WheelEvent): void {
                        if (event.angleDelta.y < 0)
                            root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, root.count - 1);
                        else if (event.angleDelta.y > 0)
                            root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
                    }

                    implicitWidth: contentCol.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: contentCol.implicitHeight + Tokens.padding.small * 2

                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onPressed: root.screenState.dashboardTab = tab.index

                    StateLayer {
                        id: stateLayer

                        anchors.fill: parent
                        radius: Tokens.rounding.medium
                        color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
                        onClicked: root.screenState.dashboardTab = tab.index
                    }

                    ColumnLayout {
                        id: contentCol
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            id: icon

                            Layout.alignment: Qt.AlignHCenter
                            text: tab.modelData.iconName
                            color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            fill: tab.current ? 1 : 0
                            fontStyle: Tokens.font.icon.medium

                            Behavior on fill {
                                Anim {
                                    type: Anim.DefaultEffects
                                }
                            }
                        }

                        StyledText {
                            id: label

                            Layout.alignment: Qt.AlignHCenter
                            text: tab.modelData.text
                            color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }
        }
    }

    Item {
        id: indicator

        anchors.top: bar.bottom
        anchors.topMargin: 5

        implicitWidth: {
            if (root.currentItem && root.currentItem.implicitWidth > 0)
                return root.currentItem.implicitWidth;
            return (root.nonAnimWidth - bar.spacing * Math.max(1, root.count - 1)) / Math.max(1, root.count);
        }
        implicitHeight: 3

        x: {
            if (root.currentItem && root.currentItem.width > 0)
                return root.currentItem.x + (root.currentItem.width - indicator.implicitWidth) / 2;
            const w = root.nonAnimWidth / Math.max(1, root.count);
            return w * root.screenState.dashboardTab + (w - implicitWidth) / 2;
        }

        clip: true

        StyledRect {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: parent.implicitHeight * 2

            color: Colours.palette.m3primary
            radius: Tokens.rounding.full
        }

        Behavior on x {
            Anim {}
        }

        Behavior on implicitWidth {
            Anim {}
        }
    }

    StyledRect {
        id: separator

        anchors.top: indicator.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }
}
