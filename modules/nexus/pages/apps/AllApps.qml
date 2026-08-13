pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property string query
    property string filter: "all"

    readonly property list<DesktopEntry> filteredApps: [...DesktopEntries.applications.values].filter(app => {
        const q = query.trim().toLowerCase();
        const searchMatch = !q || `${app.name} ${app.id} ${app.comment ?? ""} ${app.genericName ?? ""}`.toLowerCase().includes(q);
        const favourite = Strings.testRegexList(GlobalConfig.launcher.favouriteApps, app.id);
        const hidden = Strings.testRegexList(GlobalConfig.launcher.hiddenApps, app.id);
        return searchMatch && (filter === "all" || (filter === "favourites" && favourite) || (filter === "hidden" && hidden));
    }).sort((a, b) => a.name.localeCompare(b.name))

    title: qsTr("All apps")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledTextField {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.medium
            placeholderText: qsTr("Search apps")
            leadingIcon: "search"
            trailingIcon: text ? "close" : ""
            onTextChanged: root.query = text
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.large
            spacing: Tokens.spacing.medium
            FilterButton { filterValue: "all"; buttonText: qsTr("All (%1)").arg(DesktopEntries.applications.values.length); buttonIcon: "apps" }
            FilterButton { filterValue: "favourites"; buttonText: qsTr("Favourites"); buttonIcon: "favorite" }
            FilterButton { filterValue: "hidden"; buttonText: qsTr("Hidden"); buttonIcon: "visibility_off" }
        }

        Repeater {
            id: list

            model: root.filteredApps

            ConnectedRect {
                id: appItem

                required property DesktopEntry modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                last: index === list.count - 1
                implicitHeight: appRow.implicitHeight + appRow.anchors.margins * 2

                StateLayer {
                    onClicked: {
                        root.nState.selectedApp = appItem.modelData;
                        root.nState.openSubPage(2);
                    }
                }

                RowLayout {
                    id: appRow

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    IconImage {
                        asynchronous: true
                        implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.8)
                        source: Quickshell.iconPath(appItem.modelData.icon, "image-missing")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: appItem.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: text
                            text: (appItem.modelData.comment || appItem.modelData.genericName) ?? ""
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    MaterialIcon {
                        visible: Strings.testRegexList(GlobalConfig.launcher.favouriteApps, appItem.modelData.id)
                        text: "favorite"
                        fill: 1
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }

                    MaterialIcon {
                        visible: Strings.testRegexList(GlobalConfig.launcher.hiddenApps, appItem.modelData.id)
                        text: "visibility_off"
                        color: Colours.palette.m3outline
                        fontStyle: Tokens.font.icon.small
                    }

                    MaterialIcon {
                        text: "chevron_right"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.filteredApps.length === 0
            text: qsTr("No apps match the current search and filter")
            horizontalAlignment: Text.AlignHCenter
            color: Colours.palette.m3outline
            font: Tokens.font.body.medium
        }
    }

    component FilterButton: IconTextButton {
        required property string filterValue
        required property string buttonText
        required property string buttonIcon
        Layout.fillWidth: true
        text: buttonText
        icon: buttonIcon
        type: root.filter === filterValue ? ButtonBase.Filled : IconTextButton.Tonal
        onClicked: root.filter = filterValue
    }
}
