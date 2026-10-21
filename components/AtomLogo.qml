import QtQuick
import Caelestia.Config
import qs.components.effects
import qs.services

Item {
    id: root

    property color colour: Colours.palette.m3primary

    implicitWidth: 128
    implicitHeight: 128
    width: implicitWidth
    height: implicitHeight

    ColouredIcon {
        id: icon
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: Math.min(parent.width, parent.height)
        source: Qt.resolvedUrl("../assets/logo.svg")
        colour: root.colour
    }
}
