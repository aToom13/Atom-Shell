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
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property string state
    property string networkInterface
    property string networkType
    property string connectionName
    property string localAddress
    property string lastNetworkInterface
    property string lastConnectionName
    property string security
    property string pmf
    property string firewall
    property string listenerCount
    property string publicListenerCount
    property string neighbourCount
    property string ipForward
    property string promiscuous
    property string monitorSupport
    property list<var> listeners: []
    property list<var> packets: []
    property var selectedPacket
    property string captureMessage
    property string actionMessage
    property bool networkActionBusy
    property bool showAllPackets
    property bool showAllListeners

    readonly property int tcpPackets: packets.filter(packet => packet.protocol === "TCP").length
    readonly property int udpPackets: packets.filter(packet => packet.protocol === "UDP").length
    readonly property int arpPackets: packets.filter(packet => packet.protocol === "ARP").length
    readonly property int capturedBytes: packets.reduce((total, packet) => total + Number(packet.bytes || 0), 0)
    readonly property int openNetworks: Nmcli.networks.filter(network => !network.security || network.security === "--").length
    readonly property int weakNetworks: Nmcli.networks.filter(network => network.security?.toUpperCase().includes("WEP") || network.security?.toUpperCase().includes("WPA1")).length

    readonly property bool connected: state === "connected" && networkInterface
    readonly property string securityLevel: {
        const value = security.toUpperCase();
        if (!connected)
            return qsTr("Disconnected");
        if (networkType !== "wifi")
            return qsTr("Wired connection");
        if (!value || value === "--" || value.includes("WEP"))
            return qsTr("Critical");
        if (value.includes("WPA3") || value.includes("SAE"))
            return qsTr("Strong");
        if (value.includes("WPA1") || pmf === "0" || pmf === "1")
            return qsTr("Needs attention");
        return qsTr("Good");
    }
    readonly property color securityColour: securityLevel === qsTr("Critical") ? Colours.palette.m3error : securityLevel === qsTr("Needs attention") ? Colours.palette.m3tertiary : Colours.palette.m3primary

    function refresh(): void {
        if (!statusProc.running)
            statusProc.running = true;
        if (!listenersProc.running)
            listenersProc.running = true;
    }

    function parseStatus(text: string): void {
        const values = {};
        for (const line of text.trim().split("\n")) {
            const split = line.indexOf("\t");
            if (split > 0)
                values[line.slice(0, split)] = line.slice(split + 1);
        }
        state = values.state || "disconnected";
        networkInterface = values.interface || "";
        networkType = values.type || "";
        connectionName = values.connection || "";
        localAddress = values.address || "";
        if (networkInterface)
            lastNetworkInterface = networkInterface;
        if (connectionName)
            lastConnectionName = connectionName;
        security = values.security || "";
        pmf = values.pmf || "";
        firewall = values.firewall || "inactive";
        listenerCount = values.listeners || "0";
        publicListenerCount = values.public_listeners || "0";
        neighbourCount = values.neighbors || "0";
        ipForward = values.ip_forward || "0";
        promiscuous = values.promiscuous || "no";
        monitorSupport = values.monitor || "unavailable";
    }

    function parseListeners(text: string): list<var> {
        return text.trim().split("\n").filter(line => line).map(line => {
            const fields = line.split("\t");
            return { protocol: fields[0] || "", address: fields[1] || "", process: fields[2] || qsTr("system") };
        });
    }

    function parsePackets(text: string): list<var> {
        return text.trim().split("\n").filter(line => line).map(line => {
            const fields = line.split("\t");
            return { time: fields[0] || "", protocol: fields[1] || "OTHER", source: fields[2] || "", destination: fields[3] || "", bytes: fields[4] || "", summary: fields[5] || "" };
        });
    }

    function protocolIcon(protocol: string): string {
        if (protocol === "TCP") return "sync_alt";
        if (protocol === "UDP") return "swap_horiz";
        if (protocol === "ARP") return "device_hub";
        if (protocol === "ICMP") return "network_ping";
        return "data_object";
    }

    function endpointIp(endpoint: string): string {
        const match = endpoint.match(/^(\d+\.\d+\.\d+\.\d+)/);
        return match?.[1] ?? endpoint;
    }

    function endpointLabel(endpoint: string): string {
        if (!endpoint)
            return "";
        const ip = endpointIp(endpoint);
        const ownIp = localAddress.split("/")[0];
        if (ip === ownIp)
            return qsTr("This device (%1)").arg(endpoint);
        if (ip.startsWith("10.") || ip.startsWith("192.168.") || ip.match(/^172\.(1[6-9]|2[0-9]|3[01])\./))
            return qsTr("LAN device %1 (%2)").arg(ip.split(".").pop()).arg(endpoint);
        return qsTr("Internet host (%1)").arg(endpoint);
    }

    function runNetworkAction(action: string): void {
        const targetInterface = networkInterface || lastNetworkInterface;
        const targetConnection = connectionName || lastConnectionName;
        if (networkActionBusy || !targetInterface)
            return;
        networkActionBusy = true;
        actionMessage = action === "disconnect" ? qsTr("Disconnecting this device…") : qsTr("Reconnecting…");
        actionProc.command = action === "disconnect"
            ? [`${Paths.home}/.config/hypr/scripts/network-security.sh`, "disconnect", targetInterface]
            : [`${Paths.home}/.config/hypr/scripts/network-security.sh`, "reconnect", targetInterface, targetConnection];
        actionProc.running = true;
    }

    title: qsTr("Network security")
    isSubPage: true

    Component.onCompleted: refresh()

    property Process statusProcess: Process {
        id: statusProc
        command: [`${Paths.home}/.config/hypr/scripts/network-security.sh`, "status"]
        stdout: StdioCollector { onStreamFinished: root.parseStatus(text) }
    }

    property Process listenersProcess: Process {
        id: listenersProc
        command: [`${Paths.home}/.config/hypr/scripts/network-security.sh`, "listeners"]
        stdout: StdioCollector { onStreamFinished: root.listeners = root.parseListeners(text) }
    }

    property Process actionProcess: Process {
        id: actionProc
        stdout: StdioCollector { id: actionOutput }
        stderr: StdioCollector { id: actionError }
        onExited: code => {
            root.networkActionBusy = false;
            root.actionMessage = (code === 0 ? actionOutput.text : actionError.text).trim() || (code === 0 ? qsTr("Network state changed") : qsTr("Network action failed"));
            statusRefreshDelay.start();
        }
    }

    property Process captureProcess: Process {
        id: captureProc
        command: [`${Paths.home}/.config/hypr/scripts/network-security.sh`, "capture", root.networkInterface]
        stdout: StdioCollector { onStreamFinished: root.packets = root.parsePackets(text) }
        stderr: StdioCollector { id: captureError }
        onExited: code => {
            if (code !== 0 && !root.packets.length)
                root.captureMessage = captureError.text.trim() || qsTr("Packet capture failed or authorization was cancelled");
        }
    }

    property Timer statusRefreshTimer: Timer {
        id: statusRefreshDelay
        interval: 1200
        onTriggered: root.refresh()
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: overviewLayout.implicitHeight + Tokens.padding.large * 2
            color: Colours.layer(root.securityColour, 2)

            RowLayout {
                id: overviewLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large
                MaterialIcon { text: root.securityLevel === qsTr("Strong") || root.securityLevel === qsTr("Good") ? "verified_user" : "gpp_maybe"; color: root.securityColour; fontStyle: Tokens.font.icon.extraLarge }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { Layout.fillWidth: true; text: root.securityLevel; font: Tokens.font.title.medium; elide: Text.ElideRight }
                    StyledText { Layout.fillWidth: true; text: root.connected ? qsTr("%1 • %2 • %3").arg(root.connectionName).arg(root.networkInterface).arg(root.security || qsTr("No Wi-Fi security")) : qsTr("No active network connection"); color: Colours.palette.m3outline; font: Tokens.font.body.small; elide: Text.ElideRight }
                }
                IconButton { icon: "refresh"; type: IconButton.Text; onClicked: root.refresh() }
            }
        }

        SectionHeader { text: qsTr("Protection") }

        InfoRow { first: true; icon: "wifi_lock"; label: qsTr("Wi-Fi security"); value: root.security || qsTr("Not available") }
        InfoRow { icon: "encrypted"; label: qsTr("Protected management frames"); subtext: qsTr("PMF protects management traffic from spoofing"); value: root.pmf === "3" ? qsTr("Required") : root.pmf === "2" ? qsTr("Optional") : qsTr("Not enforced") }
        InfoRow { icon: "shield"; label: qsTr("Firewall"); value: root.firewall === "active" ? qsTr("Active") : qsTr("Inactive") }
        InfoRow { icon: "lan"; label: qsTr("Listening TCP/UDP sockets"); value: root.listenerCount }
        InfoRow { icon: "public"; label: qsTr("Sockets exposed on all addresses"); value: root.publicListenerCount }
        InfoRow { icon: "device_hub"; label: qsTr("Reachable LAN neighbours"); value: root.neighbourCount }
        InfoRow { icon: "route"; label: qsTr("IPv4 forwarding"); value: root.ipForward === "1" ? qsTr("Enabled") : qsTr("Disabled") }
        InfoRow { last: true; icon: "visibility"; label: qsTr("Promiscuous mode"); value: root.promiscuous === "yes" ? qsTr("Enabled") : qsTr("Disabled") }

        SectionHeader { text: qsTr("Wireless environment") }

        InfoRow { first: true; icon: "wifi_find"; label: qsTr("Visible Wi-Fi networks"); value: String(Nmcli.networks.length) }
        InfoRow { icon: "no_encryption"; label: qsTr("Open networks nearby"); value: String(root.openNetworks) }
        InfoRow { icon: "warning"; label: qsTr("Weak WEP/WPA1 networks nearby"); value: String(root.weakNetworks) }
        InfoRow { last: true; icon: "radar"; label: qsTr("Wireless monitor support"); value: root.monitorSupport === "available" ? qsTr("Available") : qsTr("Unavailable") }

        SectionHeader { text: qsTr("Connection control") }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium
            IconTextButton {
                Layout.fillWidth: true
                icon: "wifi_off"
                text: qsTr("Disconnect this device")
                type: IconTextButton.Tonal
                disabled: root.networkActionBusy || !root.connected
                onClicked: root.runNetworkAction("disconnect")
            }
            IconTextButton {
                Layout.fillWidth: true
                icon: "wifi"
                text: qsTr("Reconnect")
                type: ButtonBase.Filled
                disabled: root.networkActionBusy || !root.lastNetworkInterface || !root.lastConnectionName || root.connected
                onClicked: root.runNetworkAction("reconnect")
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.actionMessage
            text: root.actionMessage
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        SectionHeader { text: qsTr("Passive packet inspection") }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: captureIntro.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: captureIntro
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large
                MaterialIcon { text: "manage_search"; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.large }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { Layout.fillWidth: true; text: qsTr("Inspect traffic on %1").arg(root.networkInterface || qsTr("active interface")); font: Tokens.font.body.medium }
                    StyledText { Layout.fillWidth: true; text: qsTr("Captures packet metadata for up to 15 seconds. Administrator authorization is required. Packet payload is not displayed."); color: Colours.palette.m3outline; font: Tokens.font.body.small; wrapMode: Text.WordWrap }
                }
                IconTextButton {
                    icon: captureProc.running ? "stop" : "play_arrow"
                    text: captureProc.running ? qsTr("Stop") : qsTr("Capture")
                    type: captureProc.running ? IconTextButton.Tonal : ButtonBase.Filled
                    disabled: !root.connected
                    onClicked: {
                        if (captureProc.running) {
                            captureProc.running = false;
                        } else {
                            root.packets = [];
                            root.selectedPacket = null;
                            root.captureMessage = "";
                            root.showAllPackets = false;
                            captureProc.running = true;
                        }
                    }
                }
            }
        }

        InfoRow { visible: root.packets.length > 0; first: true; icon: "data_object"; label: qsTr("Captured packets"); value: String(root.packets.length) }
        InfoRow { visible: root.packets.length > 0; icon: "sync_alt"; label: qsTr("TCP / UDP / ARP"); value: `${root.tcpPackets} / ${root.udpPackets} / ${root.arpPackets}` }
        InfoRow { visible: root.packets.length > 0; last: true; icon: "straighten"; label: qsTr("Observed bytes"); value: String(root.capturedBytes) }

        StyledText { Layout.fillWidth: true; visible: captureProc.running; text: qsTr("Waiting for packet capture to finish…"); color: Colours.palette.m3outline; font: Tokens.font.body.small; horizontalAlignment: Text.AlignHCenter }
        StyledText { Layout.fillWidth: true; visible: root.captureMessage; text: root.captureMessage; color: Colours.palette.m3error; font: Tokens.font.body.small; wrapMode: Text.WordWrap }

        Repeater {
            model: root.showAllPackets ? root.packets : root.packets.slice(0, 20)
            delegate: ConnectedRect {
                required property int index
                required property var modelData
                Layout.fillWidth: true
                first: index === 0
                last: index === Math.min(root.packets.length, root.showAllPackets ? root.packets.length : 20) - 1 && root.packets.length <= 20
                implicitHeight: packetColumn.implicitHeight + Tokens.padding.medium * 2
                color: root.selectedPacket === modelData ? Colours.layer(Colours.palette.m3primaryContainer, 2) : Colours.tPalette.m3surfaceContainer
                StateLayer { onClicked: root.selectedPacket = root.selectedPacket === modelData ? null : modelData }
                ColumnLayout {
                    id: packetColumn
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium
                        MaterialIcon { text: root.protocolIcon(modelData.protocol); color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.medium }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText { Layout.fillWidth: true; text: modelData.source && modelData.destination ? `${root.endpointLabel(modelData.source)} → ${root.endpointLabel(modelData.destination)}` : modelData.summary; font: Tokens.font.body.small; elide: Text.ElideRight }
                            StyledText { Layout.fillWidth: true; text: `${modelData.time} • ${modelData.protocol}`; color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideRight }
                        }
                        StyledText { text: modelData.bytes ? qsTr("%1 B").arg(modelData.bytes) : ""; color: Colours.palette.m3outline; font: Tokens.font.label.small }
                        MaterialIcon { text: root.selectedPacket === modelData ? "expand_less" : "expand_more"; color: Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.small }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.selectedPacket === modelData
                        spacing: Tokens.spacing.extraSmall
                        StyledText { Layout.fillWidth: true; text: modelData.source ? qsTr("Source: %1").arg(root.endpointLabel(modelData.source)) : qsTr("Source unavailable"); color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.body.small; wrapMode: Text.WrapAnywhere }
                        StyledText { Layout.fillWidth: true; text: modelData.destination ? qsTr("Destination: %1").arg(root.endpointLabel(modelData.destination)) : qsTr("Destination unavailable"); color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.body.small; wrapMode: Text.WrapAnywhere }
                        StyledText { Layout.fillWidth: true; text: qsTr("Protocol: %1 • Time: %2 • Observed size: %3 bytes").arg(modelData.protocol).arg(modelData.time).arg(modelData.bytes || "0"); color: Colours.palette.m3outline; font: Tokens.font.label.small; wrapMode: Text.WordWrap }
                        StyledText { Layout.fillWidth: true; visible: modelData.summary; text: modelData.summary; color: Colours.palette.m3outline; font: Tokens.font.mono.small; wrapMode: Text.WrapAnywhere }
                    }
                }
            }
        }

        RowButton {
            visible: root.packets.length > 20
            last: true
            icon: root.showAllPackets ? "expand_less" : "expand_more"
            text: root.showAllPackets ? qsTr("Show fewer packets") : qsTr("Show %1 more packets").arg(root.packets.length - 20)
            trailingIcon: root.showAllPackets ? "keyboard_arrow_up" : "keyboard_arrow_down"
            onClicked: root.showAllPackets = !root.showAllPackets
        }

        SectionHeader { text: qsTr("Local listening services") }

        Repeater {
            model: root.showAllListeners ? root.listeners : root.listeners.slice(0, 12)
            delegate: ConnectedRect {
                required property int index
                required property var modelData
                Layout.fillWidth: true
                first: index === 0
                last: index === Math.min(root.listeners.length, root.showAllListeners ? root.listeners.length : 12) - 1 && root.listeners.length <= 12
                implicitHeight: listenerLayout.implicitHeight + Tokens.padding.medium * 2
                RowLayout {
                    id: listenerLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    MaterialIcon { text: modelData.protocol === "tcp" ? "lan" : "swap_horiz"; color: Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.small }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: modelData.address; font: Tokens.font.mono.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; text: modelData.process; color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideRight }
                    }
                    StyledText { text: modelData.protocol.toUpperCase(); color: Colours.palette.m3primary; font: Tokens.font.label.small }
                }
            }
        }

        RowButton {
            visible: root.listeners.length > 12
            last: true
            icon: root.showAllListeners ? "expand_less" : "expand_more"
            text: root.showAllListeners ? qsTr("Show fewer services") : qsTr("Show %1 more services").arg(root.listeners.length - 12)
            trailingIcon: root.showAllListeners ? "keyboard_arrow_up" : "keyboard_arrow_down"
            onClicked: root.showAllListeners = !root.showAllListeners
        }
    }
}
