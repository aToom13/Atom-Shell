import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property ScreenState screenState

    implicitWidth: Tokens.sizes.dashboard.mediaTabWidth
    implicitHeight: Tokens.sizes.dashboard.mediaTabHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: 96
            radius: Tokens.rounding.extraLarge * 1.5
            color: PhoneService.fileDragActive ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainer

            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: 60
                    implicitHeight: 60
                    radius: Tokens.rounding.extraLarge
                    color: PhoneService.ready ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: PhoneService.fileDragActive ? "download" : PhoneService.charging ? "battery_charging_full" : "smartphone"
                        color: PhoneService.ready || PhoneService.fileDragActive ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3outline
                        fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.15).build()
                        fill: PhoneService.ready || PhoneService.fileDragActive ? 1 : 0
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: PhoneService.fileDragActive ? I18n.t("Will be sent to phone on release") : PhoneService.deviceName
                        font: Tokens.font.title.large
                        color: Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: PhoneService.fileDragActive ? I18n.t("USB → Local Network → Bluetooth → Tailscale") : PhoneService.statusText
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.preferredWidth: 250
                    spacing: Tokens.spacing.extraSmall

                    TransportPill { label: "USB"; connected: PhoneService.usbConnected; available: PhoneService.usbAvailable }
                    TransportPill { label: "Wi-Fi"; connected: PhoneService.localConnected; available: PhoneService.localAvailable }
                    TransportPill { label: "BT"; connected: PhoneService.kdeReachable; available: PhoneService.kdePaired }
                    TransportPill { label: "Tail"; connected: PhoneService.tailscaleConnected; available: PhoneService.tailscaleAvailable }
                }

                ColumnLayout {
                    Layout.preferredWidth: 132
                    spacing: Tokens.spacing.extraSmall

                    RowLayout {
                        Layout.fillWidth: true

                        MaterialIcon {
                            text: PhoneService.charging ? "bolt" : PhoneService.battery >= 0 && PhoneService.battery < 20 ? "battery_alert" : "battery_full"
                            color: PhoneService.charging ? Colours.palette.m3primary : PhoneService.battery >= 0 && PhoneService.battery < 20 ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: PhoneService.battery >= 0 ? `%${PhoneService.battery}` : "--"
                            horizontalAlignment: Text.AlignRight
                            font: Tokens.font.label.large
                            color: Colours.palette.m3onSurface
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 8
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHighest

                        StyledRect {
                            width: parent.width * Math.max(0, PhoneService.battery) / 100
                            height: parent.height
                            radius: parent.radius
                            color: PhoneService.battery >= 0 && PhoneService.battery < 20 ? Colours.palette.m3error : Colours.palette.m3primary

                            Behavior on width { Anim {} }
                        }
                    }
                }

                IconButton {
                    icon: "refresh"
                    type: IconButton.Text
                    isRound: true
                    disabled: PhoneService.refreshing
                    onClicked: PhoneService.refresh(true)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.medium

            ActionCard {
                title: I18n.t("Audio & media")
                subtitle: I18n.t("Remote control")

                ActionRow {
                    ControlButton { icon: "volume_down"; text: I18n.t("Volume down"); action: "volume-down"; success: I18n.t("Phone volume lowered") }
                    ControlButton { icon: "volume_off"; text: I18n.t("Mute"); action: "mute"; success: I18n.t("Phone muted") }
                    ControlButton { icon: "volume_up"; text: I18n.t("Volume up"); action: "volume-up"; success: I18n.t("Phone volume raised") }
                }

                ActionRow {
                    ControlButton { icon: "skip_previous"; text: I18n.t("Previous"); action: "media-previous"; success: I18n.t("Previous track") }
                    ControlButton { icon: "play_pause"; text: I18n.t("Play"); action: "media-play-pause"; success: I18n.t("Action completed") }
                    ControlButton { icon: "skip_next"; text: I18n.t("Next"); action: "media-next"; success: I18n.t("Next track") }
                }
            }

            ActionCard {
                title: I18n.t("Quick tools")
                subtitle: PhoneService.modeLabel || I18n.t("No connection")

                ActionRow {
                    ControlButton { icon: "screen_share"; text: I18n.t("Mirror"); direct: true; onDirectClicked: { root.screenState.dashboard = false; PhoneService.openMirror(); } }
                    ControlButton { icon: "screenshot_monitor"; text: I18n.t("Screenshot"); action: "screenshot"; success: I18n.t("Screenshot saved") }
                    ControlButton { icon: "content_paste_go"; text: I18n.t("Clipboard"); action: "clipboard"; success: I18n.t("Clipboard sent to phone"); needsKde: true }
                }

                ActionRow {
                    ControlButton { icon: "call"; text: I18n.t("Answer"); action: "answer"; success: I18n.t("Call answered") }
                    ControlButton { icon: "notifications_active"; text: I18n.t("Ring"); action: "ring"; success: I18n.t("Phone is ringing"); needsKde: true }
                    ControlButton { icon: "notifications"; text: I18n.t("Notifications"); action: "notifications"; success: I18n.t("Notification panel opened") }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                radius: Tokens.rounding.extraLarge
                color: Colours.tPalette.m3surfaceContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.extraSmall

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            Layout.fillWidth: true
                            text: I18n.t("File transfer")
                            font: Tokens.font.title.small
                            color: Colours.palette.m3onSurface
                        }

                        IconTextButton {
                            icon: "move_to_inbox"
                            text: I18n.t("Receive files")
                            type: IconTextButton.Tonal
                            isRound: true
                            horizontalPadding: Tokens.padding.small
                            verticalPadding: 1
                            font: Tokens.font.label.small
                            onClicked: {
                                root.screenState.dashboard = false;
                                PhoneService.openLocalSend();
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Tokens.rounding.large
                        color: PhoneService.fileDragActive ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.small
                            anchors.rightMargin: Tokens.padding.small
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: PhoneService.transferRunning ? "upload" : PhoneService.fileDragActive ? "download" : "drive_file_move"
                                color: PhoneService.transferRunning || PhoneService.fileDragActive ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                fill: PhoneService.transferRunning || PhoneService.fileDragActive ? 1 : 0
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: PhoneService.transferRunning || PhoneService.fileDragActive
                                    text: PhoneService.transferRunning ? I18n.t("Transferring…") : I18n.t("Drop to send to phone")
                                    font: Tokens.font.label.large
                                    color: Colours.palette.m3onSurface
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: PhoneService.transferRunning ? (PhoneService.pendingTransfers.length === 1 ? PhoneService.fileName(PhoneService.pendingTransfers[0]) : I18n.t("%1 files", PhoneService.pendingTransfers.length)) : "USB · Wi-Fi · Bluetooth · Tailscale"
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                    elide: Text.ElideMiddle
                                }
                            }
                        }
                    }

                    StyledProgressBar {
                        Layout.fillWidth: true
                        visible: PhoneService.transferRunning
                        indeterminate: PhoneService.transferRunning
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 2

                        Repeater {
                            model: PhoneService.transferHistory.slice(0, 2)

                            StyledRect {
                                id: historyItem

                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: 27
                                radius: Tokens.rounding.large
                                color: Colours.palette.m3surfaceContainerHighest

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.padding.small
                                    spacing: Tokens.spacing.extraSmall

                                    MaterialIcon {
                                        text: historyItem.modelData.success ? "check_circle" : "error"
                                        color: historyItem.modelData.success ? Colours.palette.m3primary : Colours.palette.m3error
                                        fontStyle: Tokens.font.icon.small
                                        fill: 1
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: historyItem.modelData.name
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3onSurface
                                        elide: Text.ElideMiddle
                                    }

                                    StyledText {
                                        text: historyItem.modelData.time
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3outline
                                    }

                                    IconButton {
                                        icon: "folder_open"
                                        type: IconButton.Text
                                        isRound: true
                                        padding: 1
                                        onClicked: PhoneService.openContainingFolder(historyItem.modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component TransportPill: StyledRect {
        required property string label
        required property bool connected
        required property bool available

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: pillLabel.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        color: connected ? Colours.palette.m3primaryContainer : available ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHighest

        StyledText {
            id: pillLabel
            anchors.centerIn: parent
            text: parent.label
            font: Tokens.font.label.small
            color: parent.connected ? Colours.palette.m3onPrimaryContainer : parent.available ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3outline
        }
    }

    component ActionCard: StyledRect {
        id: card

        required property string title
        required property string subtitle
        default property alias controls: cardLayout.data

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: cardLayout
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.fillWidth: true

                StyledText { Layout.fillWidth: true; text: card.title; font: Tokens.font.title.small; color: Colours.palette.m3onSurface; elide: Text.ElideRight }
                StyledText { text: card.subtitle; font: Tokens.font.label.small; color: Colours.palette.m3outline; elide: Text.ElideRight }
            }
        }
    }

    component ActionRow: RowLayout {
        default property alias controls: row.data
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            id: row
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
        }
    }

    component ControlButton: IconTextButton {
        property string action
        property string success
        property bool direct: false
        property bool needsKde: false
        signal directClicked

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        horizontalPadding: Tokens.padding.extraSmall
        verticalPadding: Tokens.padding.extraSmall
        spacing: Tokens.spacing.extraSmall
        type: IconTextButton.Tonal
        isRound: true
        font: Tokens.font.label.builders.small.scale(0.82).build()
        disabled: PhoneService.busy || (needsKde ? !PhoneService.kdePaired : !direct && !PhoneService.hasAdbRoute)
        onClicked: {
            if (direct)
                directClicked();
            else
                PhoneService.runAction(action, success);
        }
    }
}
