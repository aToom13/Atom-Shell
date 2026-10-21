pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import qs.utils

PageBase {
    id: root

    property list<var> lanDevices: []
    property string networkInterface
    property string localAddress
    property string localSubnet
    property string gatewayAddress
    property bool lanScanning
    property string lanMessage: qsTr("Press Scan network to discover devices")
    property string lanDetail
    property string selectedLan
    property var pendingDisconnectDevice
    property bool disconnectBusy
    property string disconnectMessage

    function parseLan(text: string): list<var> {
        return text.trim().split("\n").filter(line => line).map(line => {
            const fields = line.split("\t");
            return { ip: fields[0] ?? "", name: fields[1] || qsTr("Network device"), mac: fields[2] ?? "", vendor: fields[3] ?? "", state: fields[4] ?? "", services: fields[5] ?? "" };
        }).filter(device => device.ip);
    }

    function scanLan(): void {
        if (lanScanning)
            return;
        lanScanning = true;
        lanMessage = qsTr("Scanning the local subnet with nmap…");
        lanScanProc.running = true;
    }

    function showLanDetail(device: var): void {
        selectedLan = device.ip;
        lanDetail = qsTr("Checking identity and services with nmap…");
        lanDetailProc.command = [`${Paths.home}/.config/hypr/scripts/device-discovery.sh`, "lan-detail", device.ip];
        lanDetailProc.running = true;
    }

    function disconnectDevice(): void {
        if (!pendingDisconnectDevice?.mac || disconnectBusy)
            return;
        disconnectBusy = true;
        disconnectMessage = qsTr("Running a short disconnect test, then restoring this Wi-Fi connection…");
        disconnectProc.command = [`${Paths.home}/.config/hypr/scripts/wifi-disconnect-test.sh`, pendingDisconnectDevice.mac, networkInterface, Nmcli.activeConnection];
        disconnectProc.running = true;
    }

    title: qsTr("Local network devices")
    isSubPage: true

    Component.onCompleted: networkInfoProc.running = true

    property Process networkInfoProcess: Process {
        id: networkInfoProc
        command: [`${Paths.home}/.config/hypr/scripts/device-discovery.sh`, "network-info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split("\t");
                root.networkInterface = fields[0] ?? "";
                root.localAddress = fields[1] ?? "";
                root.localSubnet = fields[2] ?? "";
                root.gatewayAddress = fields[3] ?? "";
            }
        }
    }

    property Process lanScanProcess: Process {
        id: lanScanProc
        command: [`${Paths.home}/.config/hypr/scripts/device-discovery.sh`, "lan-scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.lanDevices = root.parseLan(text);
                root.lanMessage = root.lanDevices.length ? qsTr("%1 devices discovered").arg(root.lanDevices.length) : qsTr("No devices responded");
            }
        }
        stderr: StdioCollector { id: lanScanError }
        onExited: code => {
            root.lanScanning = false;
            if (code !== 0)
                root.lanMessage = lanScanError.text.trim() || qsTr("Network scan failed");
        }
    }

    property Process lanDetailProcess: Process {
        id: lanDetailProc
        stdout: StdioCollector { onStreamFinished: root.lanDetail = text.trim() }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.lanDetail = text.trim() }
    }

    property Process disconnectProcess: Process {
        id: disconnectProc
        stdout: StdioCollector { id: disconnectOutput }
        stderr: StdioCollector { id: disconnectError }
        onExited: code => {
            root.disconnectBusy = false;
            const details = [disconnectError.text.trim(), disconnectOutput.text.trim()].filter(text => text).join("\n");
            const status = code === 0 ? qsTr("Test command finished. Device disconnection has not been verified.") : qsTr("Disconnect test failed (exit code %1).").arg(code);
            root.disconnectMessage = status + (details ? "\n" + details : "");
            if (code === 0)
                root.pendingDisconnectDevice = null;
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        InfoRow {
            first: true
            last: true
            icon: "lan"
            label: root.localSubnet || qsTr("No active IPv4 subnet")
            subtext: root.networkInterface ? qsTr("%1 • this device: %2 • gateway: %3").arg(root.networkInterface).arg(root.localAddress).arg(root.gatewayAddress) : qsTr("Connect to a network before scanning")
            value: root.lanDevices.length ? String(root.lanDevices.length) : ""
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.medium
            StyledText {
                Layout.fillWidth: true
                text: root.lanMessage
                color: Colours.palette.m3outline
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }
            IconTextButton {
                visible: root.gatewayAddress
                icon: "router"
                text: qsTr("Router controls")
                type: IconTextButton.Tonal
                onClicked: Quickshell.execDetached(["xdg-open", `http://${root.gatewayAddress}`])
            }
            IconTextButton {
                icon: root.lanScanning ? "sync" : "radar"
                text: root.lanScanning ? qsTr("Scanning…") : qsTr("Scan network")
                type: ButtonBase.Filled
                disabled: root.lanScanning || !root.localSubnet
                onClicked: root.scanLan()
            }
        }

        Repeater {
            model: root.lanDevices
            delegate: ConnectedRect {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: index === root.lanDevices.length - 1
                implicitHeight: lanLayout.implicitHeight + Tokens.padding.medium * 2
                color: root.selectedLan === modelData.ip ? Colours.layer(Colours.palette.m3primaryContainer, 2) : Colours.tPalette.m3surfaceContainer

                StateLayer { onClicked: root.showLanDetail(modelData) }

                RowLayout {
                    id: lanLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    MaterialIcon {
                        text: modelData.state === "this-device" ? "computer" : modelData.ip === root.gatewayAddress ? "router" : modelData.name.toLowerCase().includes("android") || modelData.name.toLowerCase().includes("galaxy") ? "smartphone" : "devices_other"
                        color: modelData.state === "this-device" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: modelData.name; font: Tokens.font.body.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; text: `${modelData.ip} • ${modelData.mac || qsTr("MAC unavailable")}`; color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; visible: modelData.vendor; text: modelData.vendor; color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; visible: modelData.services; text: qsTr("Services: %1").arg(modelData.services.replace(/,/g, ", ")); color: Colours.palette.m3primary; font: Tokens.font.label.small; elide: Text.ElideRight }
                    }
                    IconButton {
                        visible: modelData.state !== "this-device" && modelData.ip !== root.gatewayAddress && modelData.mac
                        icon: "wifi_off"
                        type: IconButton.Text
                        onClicked: root.pendingDisconnectDevice = modelData
                    }
                    MaterialIcon { text: "manage_search"; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.medium }
                }
            }
        }

        ConnectedRect {
            visible: !!root.pendingDisconnectDevice
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: disconnectConfirmLayout.implicitHeight + Tokens.padding.large * 2
            color: Colours.layer(Colours.palette.m3errorContainer, 2)
            RowLayout {
                id: disconnectConfirmLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium
                MaterialIcon { text: "warning"; color: Colours.palette.m3error; fontStyle: Tokens.font.icon.medium }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { Layout.fillWidth: true; text: qsTr("Temporarily disconnect %1?").arg(root.pendingDisconnectDevice?.name ?? ""); font: Tokens.font.body.medium; wrapMode: Text.WordWrap }
                    StyledText { Layout.fillWidth: true; text: qsTr("This test interrupts this computer's Wi-Fi and attempts to reconnect afterward; recovery is not guaranteed. LAN discovery does not confirm the device's access point. Disconnection is not verified and does not permanently block the device."); color: Colours.palette.m3outline; font: Tokens.font.body.small; wrapMode: Text.WordWrap }
                }
                TextButton { text: qsTr("Cancel"); type: TextButton.Tonal; disabled: root.disconnectBusy; onClicked: root.pendingDisconnectDevice = null }
                IconTextButton { icon: "wifi_off"; text: root.disconnectBusy ? qsTr("Testing…") : qsTr("Disconnect test"); type: ButtonBase.Filled; disabled: root.disconnectBusy; onClicked: root.disconnectDevice() }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.disconnectMessage
            text: root.disconnectMessage
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        ConnectedRect {
            visible: root.selectedLan
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: Math.min(lanDetailText.implicitHeight, 360) + Tokens.padding.large * 2
            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium
                StyledText {
                    id: lanDetailText
                    Layout.fillWidth: true
                    text: root.lanDetail
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 24
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.mono.small
                }
                IconButton {
                    Layout.alignment: Qt.AlignTop
                    icon: "content_copy"
                    type: IconButton.Text
                    onClicked: Quickshell.execDetached(["sh", "-c", `printf %s '${root.lanDetail.replace(/'/g, "'\\''")}' | wl-copy`])
                }
            }
        }
    }
}
