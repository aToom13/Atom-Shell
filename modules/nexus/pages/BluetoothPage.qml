pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
    readonly property bool btEnabled: adapter?.enabled ?? false
    property list<var> kdeDevices: []
    property bool kdeConnectRefreshing
    property bool kdeConnectAvailable
    property list<var> usbDevices: []
    property list<var> lanDevices: []
    property string networkInterface
    property string localAddress
    property string localSubnet
    property string gatewayAddress
    property bool lanScanning
    property string lanMessage: qsTr("Press Scan network to discover devices")
    property string usbDetail
    property string lanDetail
    property string selectedUsb
    property string selectedLan
    property string adapterName
    property string adapterAddress
    property bool sshfsAvailable
    property bool kdeActionBusy
    property string kdeActionTitle
    property string kdeActionStatus

    function refreshKdeConnect(): void {
        kdeConnectRefreshing = true;
        kdeDetectProc.running = true;
        kdeDevicesProc.running = true;
    }

    function parseKdeDevices(text: string): list<var> {
        return text.trim().split("\n").filter(line => line && !line.endsWith("devices found")).map(line => {
            const clean = line.replace(/^-\s*/, "");
            const split = clean.indexOf(": ");
            if (split >= 0)
                return { id: clean.slice(split + 2).split(/\s+/)[0], name: clean.slice(0, split) };
            const fields = clean.match(/^(\S+)\s+(.+)$/);
            return fields ? { id: fields[1], name: fields[2] } : null;
        }).filter(device => device && device.id);
    }

    function parseUsb(text: string): list<var> {
        return text.trim().split("\n").filter(line => line).map(line => {
            const fields = line.split("\t");
            return { bus: fields[0] ?? "", device: fields[1] ?? "", id: fields[2] ?? "", name: fields[3] || qsTr("USB device") };
        });
    }

    function parseLan(text: string): list<var> {
        return text.trim().split("\n").filter(line => line).map(line => {
            const fields = line.split("\t");
            return { ip: fields[0] ?? "", name: fields[1] || qsTr("Unknown device"), mac: fields[2] ?? "", vendor: fields[3] ?? "", state: fields[4] ?? "", services: fields[5] ?? "" };
        }).filter(device => device.ip);
    }

    function usbIcon(name: string): string {
        const value = name.toLowerCase();
        if (value.includes("camera")) return "photo_camera";
        if (value.includes("mouse")) return "mouse";
        if (value.includes("bluetooth")) return "bluetooth";
        if (value.includes("fingerprint")) return "fingerprint";
        if (value.includes("card")) return "sd_card";
        return "usb";
    }

    function showUsbDetail(device: var): void {
        selectedUsb = `${device.bus}:${device.device}`;
        usbDetail = qsTr("Reading device information…");
        usbDetailProc.command = [`${Paths.home}/.config/hypr/scripts/device-discovery.sh`, "usb-detail", device.bus, device.device];
        usbDetailProc.running = true;
    }

    function scanLan(): void {
        if (lanScanning)
            return;
        lanScanning = true;
        lanMessage = qsTr("Scanning the local subnet…");
        lanScanProc.running = true;
    }

    function showLanDetail(device: var): void {
        selectedLan = device.ip;
        lanDetail = qsTr("Checking latency, identity and common services…");
        lanDetailProc.command = [`${Paths.home}/.config/hypr/scripts/device-discovery.sh`, "lan-detail", device.ip];
        lanDetailProc.running = true;
    }

    function shareFile(deviceId: string): void {
        const safeId = deviceId.replace(/'/g, "'\\''");
        Quickshell.execDetached(["sh", "-c", `file=$(zenity --file-selection --title='Send with KDE Connect' 2>/dev/null); [ -n "$file" ] && kdeconnect-cli --share "$file" -d '${safeId}'`]);
    }

    function runKdeAction(title: string, action: string, deviceId: string): void {
        if (kdeActionBusy)
            return;
        if (action === "browse" && !sshfsAvailable) {
            kdeActionTitle = qsTr("File browsing needs SSHFS");
            kdeActionStatus = qsTr("Install the small sshfs package below, then try Browse again.");
            return;
        }
        kdeActionBusy = true;
        kdeActionTitle = title;
        kdeActionStatus = qsTr("Working…");
        kdeActionProc.command = [`${Paths.home}/.config/hypr/scripts/kdeconnect-action.sh`, action, deviceId];
        kdeActionProc.running = true;
    }

    title: qsTr("Connected devices")

    Component.onCompleted: {
        refreshKdeConnect();
        usbProc.running = networkInfoProc.running = adapterInfoProc.running = sshfsDetectProc.running = true;
    }

    property Process kdeDetectProcess: Process {
        id: kdeDetectProc
        command: ["sh", "-c", "command -v kdeconnect-cli >/dev/null"]
        onExited: code => root.kdeConnectAvailable = code === 0
    }

    property Process kdeDeviceProcess: Process {
        id: kdeDevicesProc
        command: ["sh", "-c", "kdeconnect-cli --refresh >/dev/null 2>&1 || true; sleep 0.4; kdeconnect-cli -a --id-name-only 2>/dev/null || true"]
        stdout: StdioCollector { onStreamFinished: root.kdeDevices = root.parseKdeDevices(text) }
        onExited: root.kdeConnectRefreshing = false
    }

    property Process usbProcess: Process {
        id: usbProc
        command: [`${Paths.home}/.config/hypr/scripts/device-discovery.sh`, "usb"]
        stdout: StdioCollector { onStreamFinished: root.usbDevices = root.parseUsb(text) }
    }

    property Process usbDetailProcess: Process {
        id: usbDetailProc
        stdout: StdioCollector { onStreamFinished: root.usbDetail = text.trim() }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.usbDetail = text.trim() }
    }

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

    property Process adapterInfoProcess: Process {
        id: adapterInfoProc
        command: ["bluetoothctl", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.match(/Name:\s*(.*)/);
                const address = text.match(/Controller\s+([0-9A-F:]+)/i);
                root.adapterName = name?.[1]?.trim() ?? "";
                root.adapterAddress = address?.[1] ?? "";
            }
        }
    }

    property Process sshfsDetectProcess: Process {
        id: sshfsDetectProc
        command: ["sh", "-c", "command -v sshfs >/dev/null"]
        onExited: code => root.sshfsAvailable = code === 0
    }

    property Process kdeActionProcess: Process {
        id: kdeActionProc
        stdout: StdioCollector { id: kdeActionOutput }
        stderr: StdioCollector { id: kdeActionError }
        onExited: code => {
            root.kdeActionBusy = false;
            root.kdeActionStatus = (code === 0 ? kdeActionOutput.text : kdeActionError.text).trim() || (code === 0 ? qsTr("Completed") : qsTr("Action failed"));
            Toaster.toast(code === 0 ? root.kdeActionTitle : qsTr("KDE Connect action failed"), root.kdeActionStatus, code === 0 ? "phonelink" : "error");
            sshfsDetectProc.running = true;
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Timer {
            running: root.visible
            repeat: true
            interval: 10000
            onTriggered: {
                if (!usbProc.running)
                    usbProc.running = true;
                if (!adapterInfoProc.running)
                    adapterInfoProc.running = true;
            }
        }

        Timer {
            // The installer runs in a visible terminal, so watch for it to
            // finish and update this page without requiring a reopen.
            running: root.visible && !root.sshfsAvailable
            repeat: true
            interval: 2000
            onTriggered: if (!sshfsDetectProc.running) sshfsDetectProc.running = true
        }

        SectionHeader {
            first: true
            text: qsTr("Bluetooth")
        }

        ToggleRow {
            first: true
            text: qsTr("Bluetooth")
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.largeIncreased
            checked: root.btEnabled
            onToggled: {
                if (root.adapter)
                    root.adapter.enabled = checked;
            }
        }

        InfoRow {
            last: true
            icon: "settings_bluetooth"
            label: root.adapterName || qsTr("Bluetooth adapter")
            subtext: root.adapterAddress
            value: root.btEnabled ? qsTr("Powered") : qsTr("Off")
        }

        SectionHeader {
            text: qsTr("KDE Connect")
        }

        InfoRow {
            visible: !root.kdeConnectAvailable || root.kdeDevices.length === 0
            first: true
            last: true
            icon: root.kdeConnectAvailable ? "phonelink" : "phonelink_off"
            label: root.kdeConnectAvailable ? qsTr("No reachable devices") : qsTr("KDE Connect is not installed")
            subtext: root.kdeConnectAvailable ? qsTr("Open KDE Connect to pair a phone or another computer") : qsTr("Install kdeconnect to share files, clipboard and notifications")
            value: root.kdeConnectRefreshing ? qsTr("Scanning…") : ""
        }

        Repeater {
            model: root.kdeDevices

            delegate: ConnectedRect {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                last: index === root.kdeDevices.length - 1
                implicitHeight: kdeDeviceLayout.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: kdeDeviceLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon { text: "smartphone"; fontStyle: Tokens.font.icon.medium }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: modelData.name; font: Tokens.font.body.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; text: qsTr("Reachable • %1").arg(modelData.id); color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideMiddle }
                    }
                    IconButton {
                        icon: "campaign"
                        type: IconButton.Text
                        onClicked: Quickshell.execDetached(["kdeconnect-cli", "--ping", "-d", modelData.id])
                    }
                    IconButton {
                        icon: "content_copy"
                        type: IconButton.Text
                        disabled: root.kdeActionBusy
                        onClicked: root.runKdeAction(qsTr("Clipboard sent to %1").arg(modelData.name), "clipboard", modelData.id)
                    }
                    IconButton {
                        icon: "upload_file"
                        type: IconButton.Text
                        onClicked: root.shareFile(modelData.id)
                    }
                    IconButton {
                        icon: "notifications_active"
                        type: IconButton.Text
                        onClicked: Quickshell.execDetached(["kdeconnect-cli", "--ring", "-d", modelData.id])
                    }
                    IconButton {
                        icon: "folder"
                        type: IconButton.Text
                        disabled: root.kdeActionBusy
                        onClicked: root.runKdeAction(qsTr("Browsing %1").arg(modelData.name), "browse", modelData.id)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.medium

            IconTextButton {
                Layout.fillWidth: true
                icon: "refresh"
                text: qsTr("Scan")
                type: IconTextButton.Tonal
                disabled: root.kdeConnectRefreshing
                onClicked: root.refreshKdeConnect()
            }

            IconTextButton {
                Layout.fillWidth: true
                icon: "phonelink_setup"
                text: qsTr("Open KDE Connect")
                type: ButtonBase.Filled
                disabled: !root.kdeConnectAvailable
                onClicked: Quickshell.execDetached(["sh", "-c", "command -v kdeconnect-app >/dev/null && exec kdeconnect-app || exec kdeconnect-settings"])
            }
        }

        ConnectedRect {
            visible: !root.sshfsAvailable || root.kdeActionStatus
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: kdeStatusLayout.implicitHeight + Tokens.padding.large * 2
            color: Colours.layer(!root.sshfsAvailable ? Colours.palette.m3errorContainer : Colours.palette.m3surfaceContainerHigh, 2)
            RowLayout {
                id: kdeStatusLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium
                MaterialIcon { text: !root.sshfsAvailable ? "folder_off" : "info"; color: !root.sshfsAvailable ? Colours.palette.m3error : Colours.palette.m3primary; fontStyle: Tokens.font.icon.medium }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { Layout.fillWidth: true; text: !root.sshfsAvailable ? qsTr("KDE Connect file support is missing") : root.kdeActionTitle; font: Tokens.font.body.small; wrapMode: Text.WordWrap }
                    StyledText { Layout.fillWidth: true; text: !root.sshfsAvailable ? qsTr("SSHFS is required to mount phone storage. Clipboard, ping and file sending work independently.") : root.kdeActionStatus; color: Colours.palette.m3outline; font: Tokens.font.label.small; wrapMode: Text.WordWrap }
                }
                IconTextButton {
                    visible: !root.sshfsAvailable
                    icon: "download"
                    text: qsTr("Install SSHFS")
                    type: ButtonBase.Filled
                    onClicked: Quickshell.execDetached([`${Paths.home}/.config/hypr/scripts/kdeconnect-action.sh`, "install-sshfs", root.kdeDevices[0]?.id ?? "local"])
                }
            }
        }

        SectionHeader {
            text: qsTr("Paired Bluetooth devices")
        }

        ItemList {
            id: savedList

            showList: root.btEnabled
            placeholderIcon: root.btEnabled ? "devices_other" : "bluetooth_disabled"
            placeholderText: root.btEnabled ? qsTr("No saved devices") : qsTr("Bluetooth disabled")

            model: ScriptModel {
                values: Bluetooth.devices.values.filter(d => d.bonded).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name)) // qmllint disable unresolved-type
            }

            delegate: StyledRect {
                id: device

                required property BluetoothDevice modelData
                readonly property bool connected: modelData && modelData.state === BluetoothDeviceState.Connected // qmllint disable unresolved-type
                readonly property bool loading: modelData && (modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting) // qmllint disable unresolved-type
                property real textOpacity: loading ? 0.5 : 1

                anchors.left: savedList.list.contentItem.left
                anchors.right: savedList.list.contentItem.right
                implicitHeight: deviceLayout.implicitHeight + deviceLayout.anchors.margins * 2
                radius: Tokens.rounding.extraSmall
                color: "transparent"

                Behavior on textOpacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                StateLayer {
                    disabled: device.loading
                    onClicked: {
                        if (!device.modelData || device.loading)
                            return;
                        device.modelData.connected = !device.connected;
                    }
                }

                RowLayout {
                    id: deviceLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: implicitHeight
                        implicitHeight: deviceIcon.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: device.connected ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                        MaterialIcon {
                            id: deviceIcon

                            anchors.centerIn: parent
                            text: Icons.getBluetoothIcon(device.modelData?.icon ?? "")
                            color: device.connected ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                            fontStyle: Tokens.font.icon.medium
                            fill: device.connected ? 1 : 0
                            opacity: device.textOpacity

                            Behavior on fill {
                                Anim {}
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        opacity: device.textOpacity

                        StyledText {
                            Layout.fillWidth: true
                            text: device.modelData?.name ?? qsTr("Unknown")
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: device.connected ? qsTr("Connected%1").arg(device.modelData?.batteryAvailable ? " • " + Math.round(device.modelData.battery * 100) + "%" : "") : qsTr("Saved")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                            animate: true
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                        implicitWidth: height

                        AnimLoader {
                            anchors.centerIn: parent
                            sourceComp: device.loading ? loadingComp : btnComp

                            Component {
                                id: btnComp

                                IconButton {
                                    icon: "settings"
                                    type: IconButton.Text
                                    padding: Tokens.padding.small
                                    inactiveOnColour: device.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                    label.fill: 0

                                    onClicked: {
                                        root.nState.selectedBtDevice = device.modelData;
                                        root.nState.openSubPage(1); // Per device info page
                                    }
                                }
                            }

                            Component {
                                id: loadingComp

                                LoadingIndicator {
                                    implicitSize: Math.round(Tokens.font.icon.medium.pointSize * 1.3)
                                }
                            }
                        }
                    }
                }
            }
        }

        RowButton {
            last: true
            icon: "add"
            text: qsTr("Pair new device")
            disabled: !root.btEnabled
            onClicked: root.nState.openSubPage(2)
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.large - parent.spacing

            first: true
            text: qsTr("Discoverable")
            subtext: qsTr("Allow nearby devices to find this one")
            disabled: !root.btEnabled
            checked: root.adapter?.discoverable ?? false
            onToggled: {
                if (root.adapter)
                    root.adapter.discoverable = checked;
            }

            Behavior on opacity {
                Anim {}
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Pairable")
            subtext: qsTr("Allow nearby devices to pair with this one")
            disabled: !root.btEnabled
            checked: root.adapter?.pairable ?? false
            onToggled: {
                if (root.adapter)
                    root.adapter.pairable = checked;
            }

            Behavior on opacity {
                Anim {}
            }
        }

        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium
            icon: "settings_bluetooth"
            text: qsTr("Bluetooth settings")
            type: IconTextButton.Tonal
            onClicked: Quickshell.execDetached([`${Paths.home}/.config/hypr/scripts/open-bluetooth-settings.sh`])
        }

        SectionHeader { text: qsTr("USB devices") }

        InfoRow {
            first: true
            last: true
            icon: "usb"
            label: qsTr("Connected USB peripherals")
            subtext: qsTr("Hubs are hidden; the list refreshes automatically")
            value: String(root.usbDevices.length)
        }

        Repeater {
            model: root.usbDevices
            delegate: ConnectedRect {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                last: index === root.usbDevices.length - 1
                implicitHeight: usbLayout.implicitHeight + Tokens.padding.medium * 2
                color: root.selectedUsb === `${modelData.bus}:${modelData.device}` ? Colours.layer(Colours.palette.m3primaryContainer, 2) : Colours.tPalette.m3surfaceContainer

                StateLayer { onClicked: root.showUsbDetail(modelData) }

                RowLayout {
                    id: usbLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    MaterialIcon { text: root.usbIcon(modelData.name); color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.medium }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: modelData.name; font: Tokens.font.body.small; elide: Text.ElideRight }
                        StyledText { Layout.fillWidth: true; text: qsTr("USB %1 • bus %2 device %3").arg(modelData.id).arg(modelData.bus).arg(modelData.device); color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideRight }
                    }
                    MaterialIcon { text: "chevron_right"; color: Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.medium }
                }
            }
        }

        ConnectedRect {
            visible: root.selectedUsb
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: Math.min(usbDetailText.implicitHeight, 300) + Tokens.padding.large * 2
            StyledText {
                id: usbDetailText
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                text: root.usbDetail
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 20
                elide: Text.ElideRight
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.mono.small
            }
        }

        SectionHeader { text: qsTr("Devices on the local network") }

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
                    MaterialIcon { text: "manage_search"; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.medium }
                }
            }
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
