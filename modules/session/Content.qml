pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Column {
    id: root

    required property ScreenState screenState
    property var hibernation: ShellState.shellRoot?.hibernation ?? null
    readonly property real hibernationPopupOpacity: hibernateSlot.reveal
    readonly property rect hibernationPopupRect: hibernateSlot.expanded || hibernateSlot.reveal > 0
        ? Qt.rect(hibernateSlot.x - hibernate.width - padding * 3, hibernateSlot.y - padding,
            hibernate.width + padding * 3, hibernate.height + padding * 2)
        : Qt.rect(0, 0, 0, 0)

    Component.onCompleted: hibernation?.refresh()

    padding: Tokens.padding.large
    rightPadding: CUtils.clamp(padding - Config.border.thickness, 0, padding)
    spacing: Tokens.spacing.large

    SessionButton {
        id: logout

        icon: Config.session.icons.logout
        command: Config.session.commands.logout

        KeyNavigation.down: shutdown

        Component.onCompleted: forceActiveFocus()

        Connections {
            function onLauncherChanged(): void {
                if (!root.screenState.launcher)
                    logout.forceActiveFocus();
            }

            target: root.screenState
        }
    }

    SessionButton {
        id: shutdown

        icon: Config.session.icons.shutdown
        command: Config.session.commands.shutdown

        KeyNavigation.up: logout
        KeyNavigation.down: gifFocus
    }

    Item {
        id: hibernateSlot

        readonly property bool expanded: hibernateHover.hovered || gifFocus.activeFocus || hibernate.activeFocus
        property real reveal: expanded ? 1 : 0
        width: Tokens.sizes.session.button
        height: Tokens.sizes.session.button

        Behavior on reveal { Anim {} }

        Item {
            id: hibernateArea
            objectName: "hibernateHoverArea"
            anchors.right: parent.right
            width: parent.width + (hibernateSlot.expanded ? hibernate.width + root.padding * 3 : 0)
            height: parent.height
            HoverHandler {
                id: hibernateHover
                function followPointer(): void {
                    if (!hovered)
                        return;
                    if (point.position.x >= hibernate.x && point.position.x <= hibernate.x + hibernate.width)
                        hibernate.forceActiveFocus();
                    else if (point.position.x >= gifFocus.x)
                        gifFocus.forceActiveFocus();
                }
                onHoveredChanged: followPointer()
                onPointChanged: followPointer()
            }

        AnimatedImage {
            objectName: "hibernateGif"
            anchors.right: parent.right
            width: hibernateSlot.width
            height: hibernateSlot.height
            sourceSize.width: width * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)
            playing: visible
            asynchronous: true
            speed: Config.general.sessionGifSpeed
            source: Paths.absolutePath(Config.paths.sessionGif)
            fillMode: AnimatedImage.PreserveAspectFit
        }

        Item {
            id: gifFocus
            objectName: "hibernateGifFocus"
            anchors.right: parent.right
            width: hibernateSlot.width
            height: hibernateSlot.height
            activeFocusOnTab: true
            KeyNavigation.up: shutdown
            KeyNavigation.down: windows
            KeyNavigation.left: hibernate
            KeyNavigation.tab: hibernate
            KeyNavigation.backtab: shutdown
            Keys.onEscapePressed: root.screenState.session = false
            Accessible.role: Accessible.Button
            Accessible.name: I18n.t("Hibernation options")
            Accessible.description: I18n.t("Use left arrow key to switch to Hibernate button.")
            Accessible.onPressAction: hibernate.forceActiveFocus()

            IconButton {
                objectName: "hibernateArrow"
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                icon: "chevron_left"
                type: IconButton.Text
                opacity: hibernateSlot.reveal
                enabled: hibernateSlot.expanded
                onClicked: hibernate.forceActiveFocus()
                Accessible.role: Accessible.Button
                Accessible.name: I18n.t("Switch to Hibernate button")
                Accessible.onPressAction: hibernate.forceActiveFocus()
            }
        }

        SessionButton {
            id: hibernate
            objectName: "hibernateButton"
            x: parent.width - hibernateSlot.width - width - root.padding * 2
                + (1 - hibernateSlot.reveal) * Tokens.spacing.large
            width: Tokens.sizes.session.button
            height: parent.height
            icon: "bedtime"
            disabledOnColour: inactiveOnColour
            command: []
            action: () => root.hibernation?.request()
            disabled: !root.hibernation?.armed || root.hibernation.busy
                || !root.hibernation.powerReady
                || !root.hibernation.supported
            opacity: hibernateSlot.reveal
            KeyNavigation.up: shutdown
            KeyNavigation.down: windows
            KeyNavigation.right: gifFocus
            KeyNavigation.backtab: gifFocus
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Hazırda beklet")
            Accessible.description: root.hibernation?.reason ?? qsTr("Hazırda bekletme servisi hazır değil.")
            Accessible.onPressAction: exec()
            Controls.ToolTip.visible: hovered || activeFocus
            Controls.ToolTip.text: qsTr("Hazırda beklet") + "\n"
                + (root.hibernation?.reason ?? qsTr("Hazırda bekletme servisi hazır değil."))
            Controls.ToolTip.delay: 500
        }
        }
    }

    SessionButton {
        id: windows

        icon: "window"
        command: ["sudo", "-n", "/usr/local/bin/reboot-to-windows"]

        KeyNavigation.up: gifFocus
        KeyNavigation.down: reboot
    }

    SessionButton {
        id: reboot

        icon: Config.session.icons.reboot
        command: Config.session.commands.reboot

        KeyNavigation.up: windows
    }

    component SessionButton: IconButton {
        id: button

        required property list<string> command
        property var action: null

        function exec(): void {
            if (disabled)
                return;
            if (action)
                action();
            else if (!SessionManager.exec(command))
                Quickshell.execDetached(command);
        }

        activeFocusOnTab: true
        KeyNavigation.tab: KeyNavigation.down
        KeyNavigation.backtab: KeyNavigation.up

        implicitWidth: Tokens.sizes.session.button
        implicitHeight: Tokens.sizes.session.button

        inactiveColour: activeFocus ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        inactiveOnColour: activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
        radius: pressed ? Tokens.rounding.medium : activeFocus ? Tokens.rounding.extraLarge : Tokens.rounding.largeIncreased
        font: Tokens.font.icon.builders.large.scale(1.3).build()
        onClicked: exec()
        onHoveredChanged: if (hovered) forceActiveFocus()

        Keys.onEnterPressed: exec()
        Keys.onReturnPressed: exec()
        Keys.onSpacePressed: exec()
        Keys.onEscapePressed: root.screenState.session = false
        Keys.onPressed: event => {
            if (!Config.session.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if ((event.key === Qt.Key_J || event.key === Qt.Key_N) && KeyNavigation.down) {
                    KeyNavigation.down.focus = true;
                    event.accepted = true;
                } else if ((event.key === Qt.Key_K || event.key === Qt.Key_P) && KeyNavigation.up) {
                    KeyNavigation.up.focus = true;
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab && KeyNavigation.down) {
                KeyNavigation.down.focus = true;
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                if (KeyNavigation.up) {
                    KeyNavigation.up.focus = true;
                    event.accepted = true;
                }
            }
        }
    }
}
