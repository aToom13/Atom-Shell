pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var profile: nState.selectedSavedWifiProfile
    property string password
    property string qrSvg
    property string errorMessage
    property bool revealPassword: nState.revealSavedWifiPassword
    readonly property bool loading: passwordProc.running || qrProc.running

    title: qsTr("Share Wi-Fi")
    isSubPage: true

    Component.onCompleted: {
        if (!profile?.uuid)
            return;
        passwordProc.command = ["nmcli", "--show-secrets", "-g", "802-11-wireless-security.psk", "connection", "show", "uuid", profile.uuid];
        qrProc.command = [`${Paths.home}/.config/hypr/scripts/wifi-qr.sh`, profile.uuid, profile.name];
        passwordProc.running = qrProc.running = true;
    }

    property Process passwordProcess: Process {
        id: passwordProc
        stdout: StdioCollector { onStreamFinished: root.password = text.trim() }
        stderr: StdioCollector { id: passwordError }
        onExited: code => {
            if (code !== 0)
                root.errorMessage = passwordError.text.trim() || qsTr("Could not read the saved password");
        }
    }

    property Process qrProcess: Process {
        id: qrProc
        stdout: StdioCollector { onStreamFinished: root.qrSvg = text.trim() }
        stderr: StdioCollector { id: qrError }
        onExited: code => {
            if (code !== 0)
                root.errorMessage = qrError.text.trim() || qsTr("Could not create the QR code");
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: networkLayout.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: networkLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large

                MaterialIcon {
                    text: "wifi_lock"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.extraLarge
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { Layout.fillWidth: true; text: root.profile?.name ?? ""; font: Tokens.font.title.medium; elide: Text.ElideRight }
                    StyledText { Layout.fillWidth: true; text: qsTr("Saved Wi-Fi profile"); color: Colours.palette.m3outline; font: Tokens.font.body.small }
                }
            }
        }

        SectionHeader { text: qsTr("Password") }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: passwordLayout.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: passwordLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: root.loading && !root.password ? qsTr("Loading…") : !root.password ? qsTr("No stored password") : root.revealPassword ? root.password : "•".repeat(Math.min(root.password.length, 24))
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.mono.medium
                    elide: Text.ElideRight
                }

                IconButton {
                    icon: root.revealPassword ? "visibility_off" : "visibility"
                    type: IconButton.Text
                    disabled: !root.password
                    onClicked: root.revealPassword = !root.revealPassword
                }

                IconButton {
                    icon: "content_copy"
                    type: IconButton.Text
                    disabled: !root.password
                    onClicked: Quickshell.execDetached(["wl-copy", root.password])
                }
            }
        }

        SectionHeader { text: qsTr("QR code") }

        ConnectedRect {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Math.min(root.cappedWidth, 360)
            implicitHeight: implicitWidth
            first: true
            last: true
            color: "white"

            Image {
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                source: root.qrSvg ? `data:image/svg+xml;charset=utf-8,${encodeURIComponent(root.qrSvg)}` : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            LoadingIndicator {
                anchors.centerIn: parent
                visible: root.loading && !root.qrSvg
                color: Colours.palette.m3primary
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.errorMessage
            text: root.errorMessage
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Scan to join %1").arg(root.profile?.name ?? "")
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
