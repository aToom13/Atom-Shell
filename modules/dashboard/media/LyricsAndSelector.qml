import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    readonly property bool phoneSource: PhoneService.mediaAvailable && (PhoneService.selectedMediaSource === "phone" || !Players.active || (PhoneService.selectedMediaSource === "auto" && PhoneService.mediaPlaying && !(Players.active?.isPlaying ?? false)))
    readonly property var sources: {
        const values = [];
        for (const player of Players.list)
            values.push(player);
        if (PhoneService.mediaAvailable)
            values.push("phone");
        return values;
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.bottomMargin: -Tokens.spacing.medium
            spacing: Tokens.spacing.medium
            z: 1

            MaterialIcon {
                Layout.topMargin: Math.round(fontInfo.pointSize * 0.12)
                text: "lyrics"
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Lyrics")
                font: Tokens.font.title.medium
            }

            LyricsInfo {}
        }

        LyricList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            phoneSource: root.phoneSource
        }

        SplitButton {
            Layout.alignment: Qt.AlignHCenter

            type: SplitButton.Tonal
            disabled: !root.sources.length
            active: menuItems.find(m => root.phoneSource ? m.modelData === "phone" : m.modelData === Players.active) ?? menuItems[0] ?? null
            menu.onItemSelected: item => {
                if (item.modelData === "phone") {
                    PhoneService.selectedMediaSource = "phone";
                } else {
                    PhoneService.selectedMediaSource = "pc";
                    Players.manualActive = item.modelData;
                }
            }

            menuItems: playerList.instances
            fallbackIcon: "music_off"
            fallbackText: qsTr("No players")

            minLeftWidth: layout.width - expandBtn.implicitWidth - spacing
            label.Layout.maximumWidth: minLeftWidth - iconLabel.implicitWidth - textRow.spacing - textRow.anchors.horizontalCenterOffset / 2 - horizontalPadding * 2
            label.elide: Text.ElideRight

            stateLayer.disabled: true
            menuOnTop: true

            Variants {
                id: playerList

                model: root.sources

                PlayerItem {}
            }
        }
    }

    component PlayerItem: MenuItem {
        required property var modelData

        icon: (modelData === "phone" ? root.phoneSource : !root.phoneSource && modelData === Players.active) ? "check" : ""
        text: modelData === "phone" ? PhoneService.deviceName : Players.getIdentity(modelData)
        activeIcon: modelData === "phone" ? "smartphone" : "animated_images"
    }
}
