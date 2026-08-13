import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    function quickToggleEnabled(toggleId: string): bool {
        const item = Config.utilities.quickToggles.values.find(entry => entry.id === toggleId);
        return item?.enabled ?? true;
    }

    function setQuickToggle(toggleId: string, enabled: bool): void {
        const toggles = GlobalConfig.utilities.quickToggles;
        for (let i = 0; i < toggles.count; i++) {
            const item = toggles.at(i);
            if (item.id === toggleId) {
                item.enabled = enabled;
                return;
            }
        }
        toggles.insert({ id: toggleId, enabled });
    }

    function activeVpnProvider(): string {
        return GlobalConfig.utilities.vpn.provider.find(provider => typeof provider === "object" && provider.enabled)?.name ?? "none";
    }

    function setVpnProvider(name: string): void {
        if (name === "none") {
            GlobalConfig.utilities.vpn.enabled = false;
            GlobalConfig.utilities.vpn.provider = [];
            return;
        }
        const existing = GlobalConfig.utilities.vpn.provider.find(provider => typeof provider === "object" && provider.name === name);
        GlobalConfig.utilities.vpn.provider = [{
            name,
            enabled: true,
            interface: existing?.interface ?? (name === "wireguard" ? "wg0" : "")
        }];
        GlobalConfig.utilities.vpn.enabled = true;
    }

    function addPlayerAlias(from: string, to: string): void {
        if (!from.trim() || !to.trim())
            return;
        GlobalConfig.services.playerAliases = [...GlobalConfig.services.playerAliases.filter(alias => alias.from !== from.trim()), { from: from.trim(), to: to.trim() }];
    }

    function removePlayerAlias(from: string): void {
        GlobalConfig.services.playerAliases = GlobalConfig.services.playerAliases.filter(alias => alias.from !== from);
    }

    // Lyrics backends, ordered to match LyricsBackend::Backend (Auto, Local, LRCLIB, NetEase)
    readonly property list<MenuItem> lyricsItems: [
        MenuItem {
            text: qsTr("Auto")
        },
        MenuItem {
            text: "Local"
        },
        MenuItem {
            text: "LRCLIB"
        },
        MenuItem {
            text: "NetEase"
        }
    ]

    // GPU options + the config string each maps to (see Gpu::parseType)
    readonly property list<MenuItem> gpuItems: [
        MenuItem {
            text: qsTr("Auto")
        },
        MenuItem {
            text: "NVIDIA"
        },
        MenuItem {
            text: qsTr("Generic")
        },
        MenuItem {
            text: qsTr("None")
        }
    ]
    readonly property list<string> gpuValues: ["", "NVIDIA", "GENERIC", "None"]

    readonly property list<MenuItem> vpnItems: [
        MenuItem { text: qsTr("Disabled") },
        MenuItem { text: "WireGuard" },
        MenuItem { text: "Tailscale" },
        MenuItem { text: "NetBird" },
        MenuItem { text: "Cloudflare WARP" }
    ]
    readonly property list<string> vpnValues: ["none", "wireguard", "tailscale", "netbird", "warp"]

    function gpuKeyToIndex(key: string): int {
        const u = (key ?? "").trim().toUpperCase();
        if (u === "")
            return 0; // Auto
        if (u === "NVIDIA")
            return 1;
        if (u === "GENERIC")
            return 2;
        return 3; // None
    }

    title: qsTr("Services")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Detected running players, used as default-player options
        Variants {
            id: playerVariants

            model: [...new Set(Players.list.map(p => Players.getIdentity(p)).filter(id => id))]

            MenuItem {
                required property string modelData

                text: modelData
                icon: modelData === GlobalConfig.services.defaultPlayer ? "check" : ""
                activeIcon: "music_note"
            }
        }

        // Notifications
        SectionHeader {
            first: true
            text: qsTr("Notifications")
        }

        NavRow {
            first: true
            last: true
            icon: "notifications"
            text: qsTr("Notifications")
            subtext: qsTr("Notifications, toasts, timeouts")
            onClicked: root.nState.openSubPage(1)
        }

        // Polling
        SectionHeader {
            text: qsTr("Polling")
        }

        StepperRow {
            first: true
            label: qsTr("Media refresh")
            subtext: qsTr("How often the media position updates (ms)")
            value: GlobalConfig.dashboard.mediaUpdateInterval
            from: 100
            to: 2000
            stepSize: 50
            onMoved: v => GlobalConfig.dashboard.mediaUpdateInterval = v
        }

        StepperRow {
            label: qsTr("System stats refresh")
            subtext: qsTr("CPU, memory and GPU update interval (seconds)")
            value: GlobalConfig.dashboard.resourceUpdateInterval / 1000
            from: 0.5
            to: 10
            stepSize: 0.5
            onMoved: v => GlobalConfig.dashboard.resourceUpdateInterval = Math.round(v * 1000)
        }

        StepperRow {
            last: true
            label: qsTr("Wi-Fi rescan")
            subtext: qsTr("How often available networks are rescanned (seconds)")
            value: GlobalConfig.nexus.networkRescanInterval / 1000
            from: 5
            to: 120
            stepSize: 5
            onMoved: v => GlobalConfig.nexus.networkRescanInterval = Math.round(v * 1000)
        }

        // Media & lyrics
        SectionHeader {
            text: qsTr("Media & lyrics")
        }

        SelectRow {
            first: true
            label: qsTr("Lyrics backend")
            subtext: qsTr("Source used to fetch synced lyrics")
            menuItems: root.lyricsItems
            active: root.lyricsItems[Lyrics.preferredBackend] ?? root.lyricsItems[0]
            onSelected: item => Lyrics.preferredBackend = root.lyricsItems.indexOf(item)
        }

        SelectRow {
            label: qsTr("Default player")
            subtext: qsTr("Preferred media player when several are open")
            menuItems: playerVariants.instances
            active: menuItems.find(i => i.text === GlobalConfig.services.defaultPlayer) ?? null
            fallbackIcon: "music_note"
            fallbackText: GlobalConfig.services.defaultPlayer || qsTr("Auto")
            onSelected: item => GlobalConfig.services.defaultPlayer = item.text
        }

        Repeater {
            model: GlobalConfig.services.playerAliases
            delegate: ConnectedRect {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                last: false
                implicitHeight: aliasLayout.implicitHeight + Tokens.padding.medium * 2
                RowLayout {
                    id: aliasLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    MaterialIcon { text: "label"; fontStyle: Tokens.font.icon.small }
                    StyledText { Layout.fillWidth: true; text: `${modelData.from}  →  ${modelData.to}`; font: Tokens.font.body.small; elide: Text.ElideRight }
                    IconButton { icon: "delete"; type: IconButton.Text; onClicked: root.removePlayerAlias(modelData.from) }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            last: true
            implicitHeight: aliasInputLayout.implicitHeight + Tokens.padding.medium * 2
            RowLayout {
                id: aliasInputLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium
                StyledTextField { id: aliasFrom; Layout.fillWidth: true; placeholderText: qsTr("Player identity"); leadingIcon: "music_note" }
                StyledTextField { id: aliasTo; Layout.fillWidth: true; placeholderText: qsTr("Display name"); leadingIcon: "badge" }
                IconButton {
                    icon: "add"
                    type: IconButton.Filled
                    disabled: !aliasFrom.text.trim() || !aliasTo.text.trim()
                    onClicked: {
                        root.addPlayerAlias(aliasFrom.text, aliasTo.text);
                        aliasFrom.text = "";
                        aliasTo.text = "";
                    }
                }
            }
        }

        // Input increments
        SectionHeader {
            text: qsTr("Input increments")
        }

        StepperRow {
            first: true
            label: qsTr("Volume step")
            subtext: qsTr("Amount the volume changes per scroll (%)")
            value: Math.round(GlobalConfig.services.audioIncrement * 100)
            from: 1
            to: 50
            stepSize: 1
            onMoved: v => GlobalConfig.services.audioIncrement = v / 100
        }

        StepperRow {
            label: qsTr("Brightness step")
            subtext: qsTr("Amount the brightness changes per scroll (%)")
            value: Math.round(GlobalConfig.services.brightnessIncrement * 100)
            from: 1
            to: 50
            stepSize: 1
            onMoved: v => GlobalConfig.services.brightnessIncrement = v / 100
        }

        StepperRow {
            last: true
            label: qsTr("Max volume")
            subtext: qsTr("Upper limit for output volume (%)")
            value: Math.round(GlobalConfig.services.maxVolume * 100)
            from: 50
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.services.maxVolume = v / 100
        }

        // Service tuning
        SectionHeader {
            text: qsTr("Service tuning")
        }

        StepperRow {
            first: true
            label: qsTr("Visualiser bars")
            subtext: qsTr("Number of bars in the audio visualisers")
            value: GlobalConfig.services.visualiserBars
            from: 10
            to: 120
            stepSize: 2
            onMoved: v => GlobalConfig.services.visualiserBars = v
        }

        ToggleRow {
            text: qsTr("Smart colour scheme")
            subtext: qsTr("Derive theme mode and variant from the wallpaper")
            checked: GlobalConfig.services.smartScheme
            onToggled: GlobalConfig.services.smartScheme = checked
        }

        SelectRow {
            last: true
            label: qsTr("GPU")
            subtext: Gpu.name ? qsTr("Monitoring: %1").arg(Gpu.name) : qsTr("Override for GPU type")
            menuOnTop: true
            menuItems: root.gpuItems
            active: root.gpuItems[root.gpuKeyToIndex(GlobalConfig.services.gpuType)]
            onSelected: item => GlobalConfig.services.gpuType = root.gpuValues[root.gpuItems.indexOf(item)]
        }

        SectionHeader { text: qsTr("Utilities panel") }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Utilities panel enabled")
            subtext: qsTr("Quick controls, recording and idle inhibition")
            checked: Config.utilities.enabled
            onToggled: GlobalConfig.utilities.enabled = checked
        }

        SectionHeader { text: qsTr("Quick toggles") }
        ToggleRow { first: true; text: qsTr("Wi-Fi"); checked: root.quickToggleEnabled("wifi"); onToggled: root.setQuickToggle("wifi", checked) }
        ToggleRow { text: qsTr("Bluetooth"); checked: root.quickToggleEnabled("bluetooth"); onToggled: root.setQuickToggle("bluetooth", checked) }
        ToggleRow { text: qsTr("Microphone"); checked: root.quickToggleEnabled("mic"); onToggled: root.setQuickToggle("mic", checked) }
        ToggleRow { text: qsTr("Settings"); checked: root.quickToggleEnabled("settings"); onToggled: root.setQuickToggle("settings", checked) }
        ToggleRow { text: qsTr("Game mode"); checked: root.quickToggleEnabled("gameMode"); onToggled: root.setQuickToggle("gameMode", checked) }
        ToggleRow { text: qsTr("Do not disturb"); checked: root.quickToggleEnabled("dnd"); onToggled: root.setQuickToggle("dnd", checked) }
        ToggleRow { last: true; text: qsTr("VPN"); checked: root.quickToggleEnabled("vpn"); onToggled: root.setQuickToggle("vpn", checked) }

        SectionHeader { text: qsTr("VPN service") }
        SelectRow {
            first: true
            last: root.activeVpnProvider() !== "wireguard"
            label: qsTr("Provider")
            subtext: qsTr("Provider used by the utilities quick toggle")
            menuItems: root.vpnItems
            active: root.vpnItems[Math.max(0, root.vpnValues.indexOf(root.activeVpnProvider()))]
            onSelected: item => root.setVpnProvider(root.vpnValues[root.vpnItems.indexOf(item)])
        }
        ConnectedRect {
            visible: root.activeVpnProvider() === "wireguard"
            Layout.fillWidth: true
            last: true
            implicitHeight: wgLayout.implicitHeight + Tokens.padding.medium * 2
            RowLayout {
                id: wgLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium
                StyledTextField {
                    id: wgInterface
                    Layout.fillWidth: true
                    placeholderText: qsTr("WireGuard interface (for example wg0)")
                    leadingIcon: "vpn_key"
                    text: GlobalConfig.utilities.vpn.provider[0]?.interface ?? "wg0"
                    onAccepted: {
                        GlobalConfig.utilities.vpn.provider = [{ name: "wireguard", enabled: true, interface: text.trim() || "wg0" }];
                        focus = false;
                    }
                }
            }
        }
    }
}
