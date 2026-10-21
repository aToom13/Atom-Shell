pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property var hibernation
    required property ScreenState screenState

    readonly property bool active: hibernation.dialogVisible
        && (ShellState.forActive() === screenState
            || (ShellState.forActive() === null && Quickshell.screens[0] === screenState.modelData))
    readonly property bool reserve: hibernation.dialogStage === "reserve"

    anchors.fill: parent
    visible: opacity > 0
    opacity: active ? 1 : 0
    focus: active

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onWheel: event => event.accepted = true
        onClicked: {}
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, 0.72)
    }

    StyledRect {
        id: card

        readonly property real reveal: root.active ? 1 : 0

        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.padding.extraLargeIncreased * 2, 520)
        height: content.implicitHeight + Tokens.padding.extraLargeIncreased * 2
        radius: Tokens.rounding.extraLargeIncreased
        color: Colours.tPalette.m3surfaceContainer
        border.color: Qt.alpha(Colours.palette.m3outline, 0.45)
        border.width: Math.max(1, Config.border.clampedThickness)
        opacity: reveal
        scale: 0.94 + reveal * 0.06
        focus: root.active

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }

        ColumnLayout {
            id: content

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraLargeIncreased
            spacing: Tokens.spacing.large

            AnimatedImage {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: root.reserve ? 240 : 210
                Layout.preferredHeight: root.reserve ? 158 : 172
                source: Paths.absolutePath(Config.paths.mediaGif)
                asynchronous: true
                playing: root.active
                fillMode: AnimatedImage.PreserveAspectFit
            }

            StyledText {
                Layout.fillWidth: true
                text: root.reserve ? I18n.t("System shutting down") : I18n.t("Low battery")
                color: Colours.palette.m3onSurface
                font: Tokens.font.title.builders.large.weight(Font.DemiBold).build()
                horizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.reserve
                text: root.reserve
                    ? I18n.t("System will hibernate in %1 seconds.", root.hibernation.dialogCountdown)
                    : ""
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                horizontalAlignment: Text.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                spacing: Tokens.spacing.medium

                Item {
                    Layout.fillWidth: true
                    visible: root.reserve
                }

                TextButton {
                    id: continueButton

                    Layout.fillWidth: !root.reserve
                    Layout.preferredHeight: Tokens.sizes.session.button
                    visible: !root.reserve
                    text: I18n.t("Continue")
                    type: TextButton.Tonal
                    activeFocusOnTab: true
                    onClicked: root.hibernation.dialogContinue()
                    KeyNavigation.right: hibernateButton
                    KeyNavigation.backtab: hibernateButton
                    label.horizontalAlignment: Text.AlignHCenter
                }

                TextButton {
                    id: hibernateButton

                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.sizes.session.button
                    text: root.reserve ? I18n.t("Shut down now") : I18n.t("Hibernate")
                    type: TextButton.Filled
                    activeFocusOnTab: true
                    onClicked: root.hibernation.dialogHibernate()
                    KeyNavigation.left: root.reserve ? null : continueButton
                    KeyNavigation.tab: root.reserve ? null : continueButton
                    label.horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    onActiveChanged: {
        if (!active)
            return;
        forceActiveFocus();
        Qt.callLater(() => hibernateButton.forceActiveFocus());
    }

    Keys.onEscapePressed: event => {
        if (root.reserve) {
            event.accepted = false;
            return;
        }
        root.hibernation.dialogContinue();
        event.accepted = true;
    }
}
