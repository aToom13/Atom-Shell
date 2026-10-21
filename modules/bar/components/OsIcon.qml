import QtQuick
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.6)
    implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.6)
    width: implicitWidth
    height: implicitHeight

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const screenState = ShellState.forActive();
            screenState.launcher = !screenState.launcher;
        }
    }

    Loader {
        asynchronous: false
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        sourceComponent: atomLogo
    }

    Component {
        id: atomLogo

        AtomLogo {
            anchors.fill: parent
            colour: Colours.palette.m3primary
        }
    }

    Component {
        id: distroIcon

        ColouredIcon {
            source: SysInfo.osLogo
            implicitSize: Math.round(Tokens.font.body.large.pointSize * 1.2)
            colour: Colours.palette.m3tertiary
        }
    }
}
