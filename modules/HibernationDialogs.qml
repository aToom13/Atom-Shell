pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia
import qs.components.containers
import qs.services

Scope {
    id: dialogScope

    required property var hibernation

    Variants {
        model: Screens.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            readonly property bool activeOutput: Hypr.monitorFor(modelData) === Hypr.focusedMonitor
                || (Hypr.focusedMonitor === null && Quickshell.screens[0] === modelData)

            screen: modelData
            name: "hibernation-dialog"
            visible: dialogScope.hibernation?.dialogVisible && activeOutput
            color: "transparent"

            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: visible ? null : emptyMask

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region {
                id: emptyMask
            }

            HibernationDialog {
                hibernation: dialogScope.hibernation
                screenState: ShellState.forScreen(win.modelData)
            }
        }
    }
}
