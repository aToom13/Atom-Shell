pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.utils

Item {
    id: root

    required property ScreenState screenState
    readonly property FileDialog facePicker: FileDialog {
        title: qsTr("Select a profile picture")
        filterLabel: qsTr("Image files")
        filters: Images.validImageExtensions
        onAccepted: path => {
            if (CUtils.copyFile(Qt.resolvedUrl(path), Qt.resolvedUrl(`${Paths.home}/.face`)))
                Quickshell.execDetached(["notify-send", "-a", "Atom Shell", "-u", "low", "-h", `STRING:image-path:${path}`, qsTr("Profile picture changed"), qsTr("Profile picture changed to %1").arg(Paths.shortenHome(path))]);
            else
                Quickshell.execDetached(["notify-send", "-a", "Atom Shell", "-u", "critical", qsTr("Unable to change profile picture"), qsTr("Failed to change profile picture to %1").arg(Paths.shortenHome(path))]);
        }
    }

    readonly property real nonAnimHeight: (content.item as Content)?.nonAnimHeight ?? 0
    readonly property bool shouldBeActive: screenState.dashboard && Config.dashboard.enabled && content.status === Loader.Ready
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.topMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth
    width: implicitWidth
    height: implicitHeight
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim { type: Anim.FastSpatial }
    }

    Loader {
        id: content

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        active: Config.dashboard.enabled

        sourceComponent: Content {
            screenState: root.screenState
            facePicker: root.facePicker
        }
    }
}
