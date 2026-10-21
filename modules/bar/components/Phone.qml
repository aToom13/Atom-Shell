import QtQuick
import Quickshell
import qs.components
import qs.services

Item {
    id: root

    implicitWidth: Math.max(icon.implicitHeight, content.implicitWidth) + Tokens.padding.small
    implicitHeight: icon.implicitHeight

    Row {
        id: content

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter

            text: !PhoneService.ready ? "smartphone" : PhoneService.charging ? "battery_charging_full" : PhoneService.battery < 20 ? "battery_alert" : "battery_full"
            color: !PhoneService.ready ? Colours.palette.m3outlineVariant : PhoneService.charging ? Colours.palette.m3primary : PhoneService.battery < 20 ? Colours.palette.m3error : Colours.palette.m3onSurface
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: PhoneService.adbReady && PhoneService.battery >= 0
            text: `%${PhoneService.battery}`
            font: Tokens.font.body.builders.small.scale(0.9).build()
            color: Colours.palette.m3onSurface
        }
    }

    StateLayer {
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: parent.implicitWidth + Tokens.padding.small
        implicitHeight: parent.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: false
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        onClicked: event => {
            if (event.button === Qt.LeftButton)
                PhoneService.openMirror();
            else if (event.button === Qt.MiddleButton)
                PhoneService.runAction("answer", I18n.t("Call answered"));
            else if (event.button === Qt.RightButton)
                PhoneService.runAction("ring", I18n.t("Phone is ringing"));
        }
    }
}
