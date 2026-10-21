pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property bool connecting: false
    property bool failed: false
    readonly property var network: nState.pendingPasswordNetwork
    readonly property bool wpaNetwork: network?.security.toUpperCase().includes("WPA") ?? false

    title: qsTr("Wi-Fi password")
    isSubPage: true

    Component.onCompleted: passwordField.forceActiveFocus()

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
                    fontStyle: Tokens.font.icon.extraLarge
                    color: Colours.palette.m3primary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.network?.ssid ?? ""
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.network?.security || qsTr("Secured network")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }
                }
            }
        }

        StyledTextField {
            id: passwordField

            Layout.fillWidth: true
            placeholderText: qsTr("Password")
            leadingIcon: "key"
            echoMode: TextInput.Password
            supportingText: root.wpaNetwork ? qsTr("WPA passwords are at least 8 characters") : qsTr("Enter this network’s password")
            errorText: root.failed ? qsTr("Connection failed — check the password") : qsTr("Password is required")

            onAccepted: root.connect()
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Tokens.spacing.small

            TextButton {
                Layout.fillHeight: true
                isRound: true
                horizontalPadding: Tokens.padding.extraLarge
                type: TextButton.Tonal
                text: qsTr("Cancel")
                onClicked: root.nState.closeSubPage()
            }

            ButtonBase {
                id: connectButton

                shapeMorph: true
                isRound: true
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                stateLayer.disabled: root.connecting || passwordField.text.length === 0
                implicitWidth: connectMetrics.width + Tokens.padding.extraLarge * 2
                implicitHeight: connectMetrics.height + Tokens.padding.medium * 2

                onClicked: root.connect()

                TextMetrics {
                    id: connectMetrics

                    text: qsTr("Connect")
                    font: connectButton.font
                }

                AnimLoader {
                    anchors.centerIn: parent
                    sourceComp: root.connecting ? loadingComp : textComp

                    Component {
                        id: loadingComp

                        LoadingIndicator {
                            implicitSize: Math.round(Tokens.font.body.medium.pointSize * 1.4)
                            color: connectButton.onColour
                        }
                    }

                    Component {
                        id: textComp

                        StyledText {
                            text: connectMetrics.text
                            font: connectButton.font
                            color: connectButton.onColour
                        }
                    }
                }
            }
        }
    }

    function connect(): void {
        const target = root.network;
        if (!target || root.connecting)
            return;

        if (passwordField.text.length === 0 || (root.wpaNetwork && passwordField.text.length < 8)) {
            passwordField.isError = true;
            passwordField.forceActiveFocus();
            return;
        }

        root.failed = false;
        root.connecting = true;
        NetworkConnection.connectWithPassword(target, passwordField.text, result => {
            root.connecting = false;

            if (result?.success) {
                root.nState.pendingPasswordNetwork = null;
                root.nState.closeSubPage();
                return;
            }

            root.failed = true;
            passwordField.isError = true;
            passwordField.forceActiveFocus();

            if (result?.needsPassword)
                Nmcli.forgetNetwork(target.ssid);
        });
    }
}
