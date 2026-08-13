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

PageBase {
    id: root

    property string connectivity: qsTr("Checking…")
    property string networkState: ""
    property list<var> vpnProfiles: []
    property list<var> savedWifiProfiles: []
    property list<string> activeVpnUuids: []
    property bool vpnBusy
    property string vpnMessage: ""
    property string activeDevice
    property string activeType
    property string activeConnection
    property string ipv4Address
    property string gateway
    property string dnsServers
    property string macAddress
    property string mtu
    property string wifiSignal
    property string wifiRate
    property string wifiSecurity
    property string wifiChannel
    property bool diagnosing
    property string diagnosticResult
    property bool networkActionBusy
    property string pendingForgetUuid
    property string pendingForgetName

    function parseRows(text: string): list<var> {
        return text.trim().split("\n").filter(line => line).map(line => {
            const fields = line.split("\t");
            return { name: fields[0] ?? "", uuid: fields[1] ?? "", type: fields[2] ?? "" };
        });
    }

    function refreshStatus(): void {
        statusProc.running = vpnProc.running = activeVpnProc.running = savedWifiProc.running = true;
    }

    function parseStatus(text: string): void {
        const values = {};
        for (const line of text.trim().split("\n")) {
            const split = line.indexOf("\t");
            if (split > 0)
                values[line.slice(0, split)] = line.slice(split + 1);
        }
        connectivity = values.connectivity || qsTr("Unknown");
        networkState = values.state || "";
        activeDevice = values.device || "";
        activeType = values.type || "";
        activeConnection = values.connection || "";
        ipv4Address = values.address || "";
        gateway = values.gateway || "";
        dnsServers = values.dns || "";
        macAddress = values.mac || "";
        mtu = values.mtu || "";
        wifiSignal = values.signal || "";
        wifiRate = values.rate || "";
        wifiSecurity = values.security || "";
        wifiChannel = values.channel || "";
    }

    function runDiagnostics(): void {
        if (diagnosing)
            return;
        diagnosing = true;
        diagnosticResult = qsTr("Testing gateway, routing, DNS and HTTPS…");
        diagnosticProc.running = true;
    }

    function runNetworkAction(title: string, command: list<string>): void {
        if (networkActionBusy)
            return;
        networkActionBusy = true;
        vpnMessage = title;
        networkAction.command = command;
        networkAction.running = true;
    }

    function setVpn(uuid: string, enabled: bool): void {
        if (vpnBusy || !uuid)
            return;
        vpnBusy = true;
        vpnMessage = enabled ? qsTr("Connecting VPN…") : qsTr("Disconnecting VPN…");
        vpnAction.command = ["nmcli", "connection", enabled ? "up" : "down", "uuid", uuid];
        vpnAction.running = true;
    }

    function parseSavedWifi(text: string): list<var> {
        return text.trim().split("\n").filter(line => line).map(line => {
            const match = line.match(/^(.*):([0-9a-fA-F-]{36}):([^:]+)$/);
            return match ? { name: match[1].replace(/\\:/g, ":"), uuid: match[2], type: match[3] } : null;
        }).filter(item => item && item.type === "802-11-wireless");
    }

    function forgetNetwork(uuid: string): void {
        const profile = savedWifiProfiles.find(item => item.uuid === uuid);
        if (!uuid || !profile)
            return;
        pendingForgetUuid = uuid;
        pendingForgetName = profile.name;
    }

    function confirmForgetNetwork(): void {
        if (!pendingForgetUuid)
            return;
        forgetProc.command = ["nmcli", "connection", "delete", "uuid", pendingForgetUuid];
        pendingForgetUuid = "";
        pendingForgetName = "";
        forgetProc.running = true;
    }

    title: qsTr("Network")

    Component.onCompleted: refreshStatus()

    property Process statusProcess: Process {
        id: statusProc
        command: [`${Paths.home}/.config/hypr/scripts/network-diagnostics.sh`, "status"]
        stdout: StdioCollector { onStreamFinished: root.parseStatus(text) }
    }

    property Process vpnProcess: Process {
        id: vpnProc
        command: ["sh", "-c", "nmcli -t -f NAME,UUID,TYPE connection show | awk -F: '$3 ~ /vpn|wireguard/ {printf \"%s\\t%s\\t%s\\n\", $1, $2, $3}'"]
        stdout: StdioCollector { onStreamFinished: root.vpnProfiles = root.parseRows(text) }
    }

    property Process activeVpnProcess: Process {
        id: activeVpnProc
        command: ["sh", "-c", "nmcli -t -f UUID,TYPE connection show --active | awk -F: '$2 ~ /vpn|wireguard/ {print $1}'"]
        stdout: StdioCollector { onStreamFinished: root.activeVpnUuids = text.trim().split("\n").filter(v => v) }
    }

    property Process savedWifiProcess: Process {
        id: savedWifiProc
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE", "connection", "show"]
        stdout: StdioCollector { onStreamFinished: root.savedWifiProfiles = root.parseSavedWifi(text) }
    }

    property Process forgetProcess: Process {
        id: forgetProc
        stdout: StdioCollector { id: forgetOutput }
        stderr: StdioCollector { id: forgetError }
        onExited: code => {
            Toaster.toast(code === 0 ? qsTr("Saved network removed") : qsTr("Network error"), (code === 0 ? forgetOutput.text : forgetError.text).trim() || qsTr("Connection profile updated"), code === 0 ? "delete" : "error");
            root.refreshStatus();
        }
    }

    property Process vpnActionProcess: Process {
        id: vpnAction
        stdout: StdioCollector { onStreamFinished: root.vpnMessage = text.trim() }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.vpnMessage = text.trim() }
        onExited: code => {
            root.vpnBusy = false;
            Toaster.toast(code === 0 ? qsTr("VPN changed") : qsTr("VPN error"), root.vpnMessage || (code === 0 ? qsTr("Connection state updated") : qsTr("Could not change the connection")), code === 0 ? "vpn_key" : "error");
            root.refreshStatus();
        }
    }

    property Process diagnosticProcess: Process {
        id: diagnosticProc
        command: [`${Paths.home}/.config/hypr/scripts/network-diagnostics.sh`, "diagnose"]
        stdout: StdioCollector { onStreamFinished: root.diagnosticResult = text.trim() }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.diagnosticResult = text.trim() }
        onExited: root.diagnosing = false
    }

    property Process networkActionProcess: Process {
        id: networkAction
        stdout: StdioCollector { id: networkActionOutput }
        stderr: StdioCollector { id: networkActionError }
        onExited: code => {
            root.networkActionBusy = false;
            Toaster.toast(code === 0 ? qsTr("Network action completed") : qsTr("Network action failed"), (code === 0 ? networkActionOutput.text : networkActionError.text).trim() || root.vpnMessage, code === 0 ? "network_check" : "error");
            root.refreshStatus();
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Current connection")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: connectionSummary.implicitHeight + Tokens.padding.large * 2
            color: Colours.layer(root.activeDevice && root.networkState === "connected" ? Colours.palette.m3primaryContainer : Colours.palette.m3errorContainer, 2)
            RowLayout {
                id: connectionSummary
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large
                MaterialIcon {
                    text: root.activeDevice && root.networkState === "connected" ? root.activeType === "wifi" ? Icons.getNetworkIcon(Number(root.wifiSignal || 0)) : "lan" : "public_off"
                    color: root.activeDevice && root.networkState === "connected" ? Colours.palette.m3primary : Colours.palette.m3error
                    fontStyle: Tokens.font.icon.extraLarge
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { Layout.fillWidth: true; text: root.activeConnection || qsTr("No active connection"); font: Tokens.font.title.medium; elide: Text.ElideRight }
                    StyledText { Layout.fillWidth: true; text: root.activeDevice ? qsTr("%1 • %2 • internet: %3").arg(root.activeDevice).arg(root.activeType).arg(root.connectivity) : qsTr("NetworkManager: %1").arg(root.networkState || qsTr("Unknown")); color: Colours.palette.m3outline; font: Tokens.font.body.small; elide: Text.ElideRight }
                }
                IconButton { icon: "refresh"; type: IconButton.Text; onClicked: root.refreshStatus() }
            }
        }

        InfoRow {
            first: true
            icon: "pin_drop"
            label: qsTr("IPv4 address")
            subtext: root.macAddress ? qsTr("MAC %1 • MTU %2").arg(root.macAddress).arg(root.mtu) : ""
            value: root.ipv4Address || qsTr("None")
        }

        InfoRow {
            icon: "router"
            label: qsTr("Gateway")
            value: root.gateway || qsTr("None")
        }

        InfoRow {
            icon: "dns"
            label: qsTr("DNS servers")
            value: root.dnsServers || qsTr("None")
        }

        InfoRow {
            visible: root.activeType === "wifi"
            last: root.activeType === "wifi"
            icon: "network_check"
            label: qsTr("Wi-Fi link")
            subtext: qsTr("%1 security • channel %2").arg(root.wifiSecurity || qsTr("Unknown")).arg(root.wifiChannel || qsTr("Unknown"))
            value: root.wifiSignal ? qsTr("%1% • %2").arg(root.wifiSignal).arg(root.wifiRate) : root.wifiRate
        }

        InfoRow {
            visible: root.activeType !== "wifi"
            last: true
            icon: "settings_ethernet"
            label: qsTr("Interface")
            value: root.activeDevice || qsTr("None")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.medium
            IconTextButton {
                Layout.fillWidth: true
                icon: root.diagnosing ? "sync" : "troubleshoot"
                text: root.diagnosing ? qsTr("Testing…") : qsTr("Run diagnostics")
                type: ButtonBase.Filled
                disabled: root.diagnosing || !root.activeDevice
                onClicked: root.runDiagnostics()
            }
            IconTextButton {
                Layout.fillWidth: true
                icon: "restart_alt"
                text: qsTr("Reconnect")
                type: IconTextButton.Tonal
                disabled: root.networkActionBusy || !root.activeConnection
                onClicked: root.runNetworkAction(qsTr("Reconnecting %1").arg(root.activeConnection), ["nmcli", "connection", "up", "id", root.activeConnection])
            }
            IconButton {
                icon: "content_copy"
                type: IconButton.Tonal
                disabled: !root.activeDevice
                onClicked: Quickshell.execDetached(["sh", "-c", `printf '%s\n' 'Connection: ${root.activeConnection}' 'Interface: ${root.activeDevice}' 'Address: ${root.ipv4Address}' 'Gateway: ${root.gateway}' 'DNS: ${root.dnsServers}' 'MAC: ${root.macAddress}' | wl-copy`])
            }
        }

        ConnectedRect {
            visible: root.diagnosticResult
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            first: true
            last: true
            implicitHeight: diagnosticsText.implicitHeight + Tokens.padding.large * 2
            StyledText {
                id: diagnosticsText
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                text: root.diagnosticResult
                wrapMode: Text.WrapAnywhere
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.mono.small
            }
        }

        Timer {
            running: root.visible
            repeat: true
            interval: 10000
            onTriggered: if (!statusProc.running) root.refreshStatus()
        }

        Timer {
            running: root.visible && Nmcli.wifiEnabled
            repeat: true
            triggeredOnStart: true
            interval: GlobalConfig.nexus.networkRescanInterval
            onTriggered: Nmcli.rescanWifi()
        }

        Timer {
            id: wifiScanDelay

            interval: 100
            onTriggered: Nmcli.rescanWifi()
        }

        Connections {
            function onWifiEnabledChanged(): void {
                if (Nmcli.wifiEnabled)
                    wifiScanDelay.start();
            }

            target: Nmcli
        }

        Loader {
            Layout.fillWidth: true
            active: Nmcli.hasAvailableEthernet
            visible: active
            asynchronous: true

            sourceComponent: EthernetSection {
                nState: root.nState
                cappedWidth: root.cappedWidth
            }
        }

        SectionHeader { text: qsTr("Wi-Fi networks") }

        ToggleRow {
            first: true
            text: qsTr("Wi-Fi")
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.largeIncreased
            checked: Nmcli.wifiEnabled
            onToggled: Nmcli.enableWifi(checked)
        }

        NetworkList {
            Layout.bottomMargin: Nmcli.wifiEnabled && Nmcli.networks.length > GlobalConfig.nexus.maxNetworksShown ? 0 : -parent.spacing
            nState: root.nState
            limit: GlobalConfig.nexus.maxNetworksShown

            Behavior on Layout.bottomMargin {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        // All networks button, only when > max networks
        RowButton {
            Layout.preferredHeight: Nmcli.wifiEnabled && Nmcli.networks.length > GlobalConfig.nexus.maxNetworksShown ? implicitHeight : 0
            clip: true

            icon: "expand_content"
            text: qsTr("Show all networks (%1)").arg(Nmcli.networks.length)
            trailingIcon: "chevron_right"
            onClicked: root.nState.openSubPage(5) // All networks sub-page

            Behavior on Layout.preferredHeight {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        // Saved networks button
        RowButton {
            icon: "bookmark"
            text: qsTr("Saved networks")
            trailingIcon: "chevron_right"
            onClicked: root.nState.openSubPage(6) // Saved networks sub-page
        }

        RowButton {
            last: true
            icon: "add"
            text: qsTr("Add network")
            disabled: !Nmcli.wifiEnabled
            onClicked: root.nState.openSubPage(2) // Add network sub-page
        }

        SectionHeader { text: qsTr("Quick VPN providers") }

        // ---- Provider-managed VPN -------------------------------------------
        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("VPN")
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.largeIncreased
            checked: VPN.connected
            // Connectable as long as there's a provider and we're not mid-switch.
            disabled: VPN.connecting || VPN.disconnecting || VPN.providers.length === 0
            onToggled: VPN.toggle()

            Timer {
                running: root.visible
                repeat: true
                triggeredOnStart: true
                interval: 5000
                onTriggered: {
                    VPN.checkStatus();
                    if (VPN.connected)
                        VPN.refreshStats();
                }
            }
        }

        ItemList {
            id: providerList

            showList: true
            placeholderIcon: "add_circle"
            placeholderText: qsTr("No VPN providers configured")

            model: ScriptModel {
                values: [...VPN.providers]
            }

            delegate: Item {
                id: provider

                required property var modelData // QML types are annoying (causes null errors on destruction if typed correctly)
                readonly property bool isSelected: modelData.providerId === VPN.selectedProvider
                readonly property bool isConnected: isSelected && VPN.connected

                anchors.left: providerList.list.contentItem.left
                anchors.right: providerList.list.contentItem.right
                implicitHeight: providerLayout.implicitHeight + providerLayout.anchors.margins * 2

                StateLayer {
                    disabled: provider.isSelected
                    radius: Tokens.rounding.extraSmall
                    onClicked: {
                        if (!provider.isSelected)
                            VPN.setActiveProvider(provider.modelData.index);
                    }
                }

                RowLayout {
                    id: providerLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: implicitHeight
                        implicitHeight: providerIcon.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: provider.isConnected ? Colours.palette.m3primaryContainer : provider.isSelected ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHighest

                        MaterialIcon {
                            id: providerIcon

                            anchors.centerIn: parent
                            text: provider.isConnected || provider.isSelected ? "vpn_key" : "vpn_key_off"
                            fill: provider.isConnected ? 1 : 0
                            color: provider.isConnected ? Colours.palette.m3onPrimaryContainer : provider.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.medium
                            animate: true
                    }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: provider.modelData.displayName
                            font: Tokens.font.body.medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (!provider.isSelected)
                                    return qsTr("Tap to select");
                                if (VPN.connecting)
                                    return qsTr("Connecting...");
                                if (VPN.disconnecting)
                                    return qsTr("Disconnecting...");
                                switch (VPN.status.state) {
                                case "connected":
                                    return qsTr("Connected");
                                case "needs-auth":
                                    return VPN.status.reason || qsTr("Authentication required");
                                case "error":
                                    return VPN.status.reason || qsTr("An error occurred");
                                default:
                                    return qsTr("Selected");
                                }
                            }
                            color: {
                                if (!provider.isSelected)
                                    return Colours.palette.m3onSurfaceVariant;
                                switch (VPN.status.state) {
                                case "connected":
                                    return Colours.palette.m3primary;
                                case "needs-auth":
                                case "error":
                                    return Colours.palette.m3error;
                                default:
                                    return Colours.palette.m3secondary;
                                }
                            }
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                            animate: true
                        }
                    }

                    Item {
                        Layout.rightMargin: Tokens.spacing.small
                        opacity: provider.isConnected && root?.cappedWidth > Tokens.sizes.nexus.networkShowVpnDetailWidth ? 1 : 0
                        visible: opacity > 0

                        implicitWidth: provider.isConnected && root?.cappedWidth > Tokens.sizes.nexus.networkShowVpnDetailWidth ? providerDetailRow.implicitWidth : 0
                        implicitHeight: providerDetailRow.implicitHeight

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }

                        RowLayout {
                            id: providerDetailRow

                            anchors.right: parent.right
                            spacing: Tokens.spacing.large

                            ColumnLayout {
                                spacing: 0

                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    text: qsTr("Interface")
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    text: provider.modelData.iface
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            ColumnLayout {
                                spacing: 0

                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    text: qsTr("Current Ping")
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignRight
                                    spacing: Tokens.spacing.small

                                    StyledRect {
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: Math.round(Tokens.font.body.small.pointSize * 0.7)
                                        implicitHeight: implicitWidth
                                        radius: Tokens.rounding.full
                                        color: VPN.pingMs <= 80 ? Colours.palette.m3primary : VPN.pingMs <= 150 ? Colours.palette.m3tertiary : Colours.palette.m3error
                                    }

                                    StyledText {
                                        text: qsTr("%1 ms").arg(VPN.pingMs)
                                        color: Colours.palette.m3outline
                                        font: Tokens.font.label.small
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                        }
                    }

                    IconButton {
                        implicitWidth: implicitHeight + (Tokens.padding.large - padding) * 2
                        type: IconButton.Tonal
                        isRound: true
                        icon: "edit"
                        onClicked: {
                            root.nState.editingVpnIndex = provider.modelData.index;
                            root.nState.openSubPage(4); // Add/edit provider sub-page
                        }
                    }
                }
            }
        }

        // Add provider
        RowButton {
            last: true
            icon: "add"
            text: qsTr("Add provider")
            onClicked: {
                root.nState.editingVpnIndex = -1;
                root.nState.openSubPage(4); // Add/edit provider sub-page
            }
        }

        SectionHeader {
            visible: root.savedWifiProfiles.length > 0
            text: qsTr("Saved Wi-Fi networks")
        }

        Repeater {
            model: root.savedWifiProfiles

            delegate: ConnectedRect {
                required property var modelData
                required property int index
                visible: root.savedWifiProfiles.length > 0
                Layout.fillWidth: true
                first: index === 0
                last: index === root.savedWifiProfiles.length - 1
                implicitHeight: savedProfileLayout.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: savedProfileLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    MaterialIcon { text: "wifi_lock"; color: Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.small }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: modelData.name; font: Tokens.font.body.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; text: modelData.name === Nmcli.activeConnection ? qsTr("Connected") : qsTr("Saved profile"); color: Colours.palette.m3outline; font: Tokens.font.label.small }
                    }
                    IconButton {
                        visible: modelData.name !== Nmcli.activeConnection
                        icon: "play_arrow"
                        type: IconButton.Text
                        disabled: root.networkActionBusy
                        onClicked: root.runNetworkAction(qsTr("Connecting to %1").arg(modelData.name), ["nmcli", "connection", "up", "uuid", modelData.uuid])
                    }
                    IconButton {
                        icon: "edit"
                        type: IconButton.Text
                        onClicked: Quickshell.execDetached(["kitty", "--title", qsTr("Edit network profile"), "-e", "nmcli", "connection", "edit", "uuid", modelData.uuid])
                    }
                    IconButton {
                        icon: "delete"
                        type: IconButton.Text
                        disabled: modelData.name === Nmcli.activeConnection || forgetProc.running
                        onClicked: root.forgetNetwork(modelData.uuid)
                    }
                }
            }
        }

        ConnectedRect {
            visible: root.pendingForgetUuid
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: forgetConfirmLayout.implicitHeight + Tokens.padding.large * 2
            color: Colours.layer(Colours.palette.m3errorContainer, 2)
            RowLayout {
                id: forgetConfirmLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium
                MaterialIcon { text: "warning"; color: Colours.palette.m3error; fontStyle: Tokens.font.icon.medium }
                StyledText { Layout.fillWidth: true; text: qsTr("Forget saved network %1?").arg(root.pendingForgetName); wrapMode: Text.WordWrap; font: Tokens.font.body.small }
                TextButton { text: qsTr("Cancel"); type: TextButton.Text; onClicked: { root.pendingForgetUuid = ""; root.pendingForgetName = ""; } }
                IconTextButton { icon: "delete"; text: qsTr("Forget"); type: ButtonBase.Filled; onClicked: root.confirmForgetNetwork() }
            }
        }

        SectionHeader {
            text: qsTr("NetworkManager VPN profiles")
        }

        Repeater {
            model: root.vpnProfiles

            delegate: ConnectedRect {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: index === root.vpnProfiles.length - 1
                implicitHeight: vpnLayout.implicitHeight + Tokens.padding.medium * 2
                RowLayout {
                    id: vpnLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    MaterialIcon { text: modelData.type === "wireguard" ? "vpn_lock" : "shield_lock"; color: root.activeVpnUuids.includes(modelData.uuid) ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.medium }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: modelData.name; font: Tokens.font.body.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; text: root.activeVpnUuids.includes(modelData.uuid) ? qsTr("Connected") : modelData.type === "wireguard" ? qsTr("WireGuard tunnel") : qsTr("VPN profile"); color: Colours.palette.m3outline; font: Tokens.font.label.small }
                    }
                    IconButton { icon: "edit"; type: IconButton.Text; onClicked: Quickshell.execDetached(["kitty", "--title", qsTr("Edit VPN"), "-e", "nmcli", "connection", "edit", "uuid", modelData.uuid]) }
                    IconTextButton {
                        icon: root.activeVpnUuids.includes(modelData.uuid) ? "vpn_key_off" : "vpn_key"
                        text: root.activeVpnUuids.includes(modelData.uuid) ? qsTr("Disconnect") : qsTr("Connect")
                        type: root.activeVpnUuids.includes(modelData.uuid) ? IconTextButton.Tonal : ButtonBase.Filled
                        disabled: root.vpnBusy
                        onClicked: root.setVpn(modelData.uuid, !root.activeVpnUuids.includes(modelData.uuid))
                    }
                }
            }
        }

        InfoRow {
            visible: root.vpnProfiles.length === 0
            first: true
            last: true
            icon: "vpn_key_off"
            label: qsTr("No VPN profiles")
            subtext: qsTr("Import WireGuard or use the connection editor for OpenVPN and other providers")
            value: ""
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.medium
            IconTextButton {
                Layout.fillWidth: true
                icon: "file_open"
                text: qsTr("Import WireGuard")
                type: IconTextButton.Tonal
                onClicked: Quickshell.execDetached(["sh", "-c", "file=$(zenity --file-selection --title='Import WireGuard configuration' --file-filter='WireGuard (*.conf) | *.conf' 2>/dev/null); [ -n \"$file\" ] && nmcli connection import type wireguard file \"$file\""])
            }
            IconTextButton {
                Layout.fillWidth: true
                icon: "add"
                text: qsTr("Create VPN")
                type: ButtonBase.Filled
                onClicked: Quickshell.execDetached(["kitty", "--title", qsTr("Create VPN profile"), "-e", "nmtui", "edit"])
            }
        }

        SectionHeader { text: qsTr("Advanced") }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            IconTextButton {
                Layout.fillWidth: true
                icon: "refresh"
                text: qsTr("Refresh")
                type: IconTextButton.Tonal
                onClicked: {
                    Nmcli.rescanWifi();
                    root.refreshStatus();
                }
            }

            IconTextButton {
                Layout.fillWidth: true
                icon: "settings_ethernet"
                text: qsTr("Connection editor")
                type: ButtonBase.Filled
                onClicked: Quickshell.execDetached(["sh", "-c", "command -v nm-connection-editor >/dev/null && exec nm-connection-editor || exec kitty --title 'Network Manager' -e nmtui"])
            }

            IconTextButton {
                Layout.fillWidth: true
                icon: "cached"
                text: qsTr("Flush DNS")
                type: IconTextButton.Tonal
                onClicked: root.runNetworkAction(qsTr("DNS cache flushed"), ["resolvectl", "flush-caches"])
            }
        }
    }
}
