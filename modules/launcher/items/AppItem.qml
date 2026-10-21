import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.launcher.services

Item {
    id: root

    required property var modelData
    required property var list
    required property ScreenState screenState

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            if (root.modelData.isFolder)
                root.list.toggleFolder(root.modelData.id);
            else {
                Apps.launch(root.modelData);
                root.screenState.launcher = false;
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        IconImage {
            id: icon

            asynchronous: true
            source: {
                const iconName = root.modelData?.icon || (root.modelData?.isFolder ? "folder" : "application-x-executable");
                if (Quickshell.hasThemeIcon(iconName))
                    return Quickshell.iconPath(iconName);
                if (root.modelData?.isFolder)
                    return Quickshell.iconPath("folder", "inode-directory");
                return Quickshell.iconPath(iconName, "application-x-executable");
            }
            implicitSize: parent.height * 0.8

            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.verticalCenter: icon.verticalCenter

            implicitWidth: parent.width - icon.width - trailingIcon.width
            implicitHeight: name.implicitHeight + comment.implicitHeight

            StyledText {
                id: name

                text: root.modelData?.name ?? ""
                font: Tokens.font.body.medium
            }

            StyledText {
                id: comment

                text: (root.modelData?.comment || root.modelData?.genericName || root.modelData?.name) ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3outline

                elide: Text.ElideRight
                width: root.width - icon.width - trailingIcon.width - Tokens.rounding.extraLargeIncreased

                anchors.top: name.bottom
            }
        }

        Loader {
            id: trailingIcon

            asynchronous: true
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            active: root.modelData && (root.modelData.isFolder || Strings.testRegexList(GlobalConfig.launcher.favouriteApps, root.modelData.id))

            sourceComponent: MaterialIcon {
                text: root.modelData.isFolder ? (root.list.openFolderId === root.modelData.id ? "expand_less" : "expand_more") : "favorite"
                fill: root.modelData.isFolder ? 0 : 1
                color: root.modelData.isFolder ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
            }
        }
    }
}
