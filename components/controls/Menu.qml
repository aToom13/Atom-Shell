pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.modules.drawers

MouseArea {
    id: root

    enum Side {
        Top,
        Bottom,
        Left,
        Right
    }

    required property Item attachTo
    property Item boundsItem: parent
    property int attachSideX: Menu.Right
    property int attachSideY: Menu.Bottom
    property int thisSideX: Menu.Right
    property int thisSideY: Menu.Top
    property real marginX
    property real marginY

    property list<MenuItem> items
    property MenuItem active: items[0] ?? null
    property bool expanded
    property bool autoSelect: true

    signal itemSelected(item: MenuItem)

    parent: {
        const win = root.attachTo.QsWindow.window;
        if (!win)
            return null;
        const contentWin = win as ContentWindow; // If inside the drawer content window, put it inside the interaction wrapper so hover works
        return contentWin ? contentWin.interactionWrapper : win.contentItem;
    }
    anchors.fill: parent
    z: 1000

    enabled: expanded
    hoverEnabled: expanded
    cursorShape: expanded ? Qt.ArrowCursor : undefined
    onClicked: expanded = false

    opacity: expanded ? 1 : 0
    layer.enabled: opacity < 1

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    TransformWatcher {
        id: watcher

        a: root.parent
        b: root.attachTo
    }

    Elevation {
        id: menu

        x: {
            watcher.transform; // mapToItem is not reactive so this forces updates
            if (!root.parent || !root.boundsItem)
                return 0;
            const item = root.attachTo;
            let off = root.attachSideX === Menu.Left ? 0 : item.width;
            if (root.thisSideX === Menu.Right)
                off -= width;
            const left = root.boundsItem.mapToItem(root.parent, 0, 0).x;
            return Math.max(left, Math.min(item.mapToItem(root.parent, off, 0).x + root.marginX, left + root.boundsItem.width - width));
        }
        y: {
            watcher.transform; // mapToItem is not reactive so this forces updates
            if (!root.parent || !root.boundsItem)
                return 0;
            const item = root.attachTo;
            let off = root.attachSideY === Menu.Top ? 0 : item.height;
            if (root.thisSideY === Menu.Bottom)
                off -= height;
            const top = root.boundsItem.mapToItem(root.parent, 0, 0).y;
            return Math.max(top, Math.min(item.mapToItem(root.parent, 0, off).y + root.marginY, top + root.boundsItem.height - height));
        }

        radius: Tokens.rounding.large
        level: 2

        implicitWidth: Math.min(root.boundsItem?.width ?? 200, Math.max(200, column.implicitWidth + scroll.anchors.margins * 2))
        implicitHeight: Math.min(root.boundsItem?.height ?? 400, column.implicitHeight + scroll.anchors.margins * 2)

        transform: Scale {
            yScale: root.expanded ? 1 : 0.1
            origin.y: root.thisSideY === Menu.Bottom ? menu.height : 0

            Behavior on yScale {
                Anim {}
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onWheel: e => e.accepted = true
        }

        StyledRect {
            anchors.fill: parent
            radius: parent.radius
            color: Colours.palette.m3surfaceContainerLow

            Flickable {
                id: scroll
                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall
                contentHeight: column.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: column
                    width: scroll.width
                    spacing: 0

                    Repeater {
                        id: repeater

                        model: root.items

                        StyledRect {
                            id: item

                            required property int index
                            required property MenuItem modelData
                            readonly property bool active: modelData === root?.active

                            Layout.fillWidth: true
                            implicitWidth: menuOptionRow.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: menuOptionRow.implicitHeight + Tokens.padding.medium * 2

                            radius: active ? Tokens.rounding.medium : Tokens.rounding.extraSmall
                            topLeftRadius: index === 0 ? Tokens.rounding.medium : radius
                            topRightRadius: index === 0 ? Tokens.rounding.medium : radius
                            bottomLeftRadius: index === repeater?.count - 1 ? Tokens.rounding.medium : radius
                            bottomRightRadius: index === repeater?.count - 1 ? Tokens.rounding.medium : radius

                            color: Qt.alpha(Colours.palette.m3tertiaryContainer, active ? 1 : 0)

                            Behavior on radius {
                                Anim {}
                            }

                            StateLayer {
                                topLeftRadius: parent.topLeftRadius
                                topRightRadius: parent.topRightRadius
                                bottomLeftRadius: parent.bottomLeftRadius
                                bottomRightRadius: parent.bottomRightRadius

                                color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                                disabled: !root.expanded
                                onClicked: {
                                    root.itemSelected(item.modelData);
                                    if (root.autoSelect)
                                        root.active = item.modelData;
                                    item.modelData.clicked();
                                    root.expanded = false;
                                }
                            }

                            RowLayout {
                                id: menuOptionRow

                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: item.modelData?.icon ?? ""
                                    color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.fillWidth: true
                                    text: item.modelData?.text ?? ""
                                    elide: Text.ElideRight
                                    color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                                }

                                Loader {
                                    asynchronous: true
                                    Layout.alignment: Qt.AlignVCenter
                                    active: item.modelData?.trailingIcon.length > 0
                                    visible: active

                                    sourceComponent: MaterialIcon {
                                        text: item.modelData.trailingIcon
                                        color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
