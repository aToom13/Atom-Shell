pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root
    title: qsTr("Game Mode")
    isSubPage: true
    readonly property bool editable: GameMode.ready && !GameMode.busy && !GameMode.enabled

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.cappedWidth
        spacing: Tokens.spacing.small

        ToggleRow {
            first: true
            last: true
            text: qsTr("Game Mode")
            subtext: GameMode.busy ? qsTr("Applying changes…") : GameMode.enabled ? qsTr("Active — disable to restore your previous settings") : qsTr("Enable your selected optimisations")
            checked: GameMode.enabled
            disabled: !GameMode.ready || GameMode.busy
            onToggled: GameMode.setEnabled(checked)
        }

        InfoRow {
            first: true
            label: qsTr("Status")
            value: GameMode.error ? qsTr("Needs attention") : GameMode.busy ? qsTr("Applying…") : GameMode.enabled ? qsTr("Active") : qsTr("Off")
            icon: GameMode.error ? "error" : "gamepad"
        }
        InfoRow { label: qsTr("Current power profile"); value: GameMode.actualProfile || qsTr("Unavailable"); icon: "bolt" }
        InfoRow { label: qsTr("Dimming and idle actions"); value: GameMode.inhibitIdle ? qsTr("Blocked") : qsTr("Normal"); icon: "display_settings" }
        InfoRow {
            last: true
            label: qsTr("System sleep protection")
            value: GameMode.inhibitSleep ? (GameMode.inhibitorReady ? qsTr("Active") : qsTr("Unavailable")) : qsTr("Off")
            icon: "bedtime_off"
        }

        Note {
            visible: !!GameMode.error
            text: GameMode.error
            color: Colours.palette.m3error
            Accessible.role: Accessible.AlertMessage
        }
        RowButton {
            first: true
            last: true
            icon: "refresh"
            text: qsTr("Check current status")
            subtext: qsTr("Verify the applied Hyprland settings and power profile")
            disabled: GameMode.busy
            onClicked: GameMode.run("status")
        }
        RowButton {
            visible: !!GameMode.error && GameMode.enabled
            first: true
            last: true
            icon: "restore"
            text: qsTr("Retry restoring previous settings")
            disabled: GameMode.busy
            onClicked: GameMode.setEnabled(false)
        }
        Note {
            text: GameMode.enabled ? qsTr("Düzenlemek için kapat.") : qsTr("Yalnızca oyun modunda uygulanır.")
        }
        Note { text: GameMode.profileName ? qsTr("Profil: %1").arg(GameMode.profileName) : qsTr("Genel varsayılanlar") }

        SectionHeader { text: qsTr("Power and frame presentation") }
        Choice {
            first: true
            setting: "powerProfile"
            values: ["keep", "performance", "balanced", "power-saver"]
            label: qsTr("Power profile during Game Mode")
            subtext: qsTr("The previous profile is saved and restored afterwards")
            menuItems: [
                MenuItem { text: qsTr("Keep current") },
                MenuItem { text: qsTr("Performance") },
                MenuItem { text: qsTr("Balanced") },
                MenuItem { text: qsTr("Power saver") }
            ]
        }
        Choice {
            last: true
            setting: "vrr"
            values: ["keep", "fullscreen", "always", "off"]
            label: qsTr("Variable refresh rate (VRR)")
            subtext: qsTr("Requires a compatible display and graphics driver")
            menuItems: [
                MenuItem { text: qsTr("Keep current") },
                MenuItem { text: qsTr("Fullscreen only") },
                MenuItem { text: qsTr("Always") },
                MenuItem { text: qsTr("Off") }
            ]
        }
        Options {
            entries: [
                ["allowTearing", qsTr("Allow screen tearing"), qsTr("Allow immediate presentation for fullscreen windows")]
            ]
        }
        Note {
            text: qsTr("Tearing gecikmeyi azaltabilir; yatay kırılma yapar.")
        }

        SectionHeader { text: qsTr("Application windows") }
        Options {
            entries: [
                ["opaqueWindows", qsTr("Force opaque application windows"), qsTr("Also disable transparency drawn by the application itself")],
                ["disableBlur", qsTr("Disable window blur"), qsTr("Stop Hyprland blur and motion blur")],
                ["disableAnimations", qsTr("Disable window animations"), qsTr("Stop Hyprland window and workspace transitions")],
                ["disableShadows", qsTr("Disable window shadows and glow"), qsTr("Reduce compositor decoration effects")],
                ["removeGaps", qsTr("Remove window gaps"), qsTr("Temporarily set inner and outer gaps to zero")],
                ["squareCorners", qsTr("Square window corners"), qsTr("Override rounding, including application-specific rules")],
                ["hideBorders", qsTr("Hide window borders"), qsTr("Keep existing border widths when this is off")]
            ]
        }

        SectionHeader { text: qsTr("Shell panels and tabs") }
        Options {
            entries: [
                ["opaqueShell", qsTr("Opaque shell panels"), qsTr("Use solid panel colours without changing your saved theme")],
                ["disableShellBlur", qsTr("Disable panel and tab blur"), qsTr("Panels, workspace tabs, media effects and desktop clock")],
                ["disableShellAnimations", qsTr("Reduce shell animations"), qsTr("Remove ordinary panel and control transitions")],
                ["disableShellShadows", qsTr("Disable shell shadows"), qsTr("Panel, desktop clock and media cover shadows")]
            ]
        }

        SectionHeader { text: qsTr("Wallpaper and media activity") }
        Options {
            entries: [
                ["pauseWallpaper", qsTr("Pause video wallpaper"), qsTr("Resume only playback paused by Game Mode")],
                ["pauseVisualisers", qsTr("Pause audio visualisers"), qsTr("Stop the visualiser bars and their audio analysis")],
                ["pauseMediaArtwork", qsTr("Pause animated cover art"), qsTr("Stop rotating album artwork while keeping playback")],
                ["pauseMediaShapes", qsTr("Pause media background shapes"), qsTr("Stop continuously moving media decorations")],
                ["hideDesktopClock", qsTr("Hide desktop clock"), qsTr("Unload the desktop clock until Game Mode ends")]
            ]
        }

        SectionHeader { text: qsTr("Notifications and interruptions") }
        Options {
            entries: [
                ["muteNotifications", qsTr("Do not disturb"), qsTr("Keep notifications in history without popup interruptions")],
                ["muteToasts", qsTr("Silence routine shell messages"), qsTr("Warnings and errors remain visible")]
            ]
        }

        SectionHeader { text: qsTr("Dimming and sleep") }
        Options {
            entries: [
                ["inhibitIdle", qsTr("Prevent idle actions"), qsTr("Block automatic dimming, screen off and idle locking")],
                ["inhibitSleep", qsTr("Prevent system sleep"), qsTr("Hold a system sleep inhibitor while Game Mode is active")]
            ]
        }
        SectionHeader { text: qsTr("Game Mode preferences") }
        RowButton {
            first: true
            last: true
            icon: "settings_backup_restore"
            text: qsTr("Restore Game Mode defaults")
            subtext: qsTr("Reset only the options on this page")
            disabled: !root.editable
            onClicked: GameMode.run("defaults")
        }
    }

    component Note: StyledText {
        Layout.fillWidth: true
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
        wrapMode: Text.Wrap
    }

    component Options: ColumnLayout {
        id: options
        required property var entries
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall / 2
        Repeater {
            model: options.entries
            ToggleRow {
                required property var modelData
                required property int index
                first: index === 0
                last: index === options.entries.length - 1
                text: modelData[1]
                subtext: modelData[2]
                checked: GameMode.settings[modelData[0]] ?? false
                disabled: !root.editable
                onToggled: GameMode.configure(modelData[0], checked)
            }
        }
    }

    component Choice: SelectRow {
        required property string setting
        required property var values
        autoSelect: false
        enabled: root.editable
        opacity: enabled ? 1 : 0.55
        active: menuItems[Math.max(0, values.indexOf(GameMode.settings[setting]))]
        onSelected: item => GameMode.configure(setting, values[menuItems.indexOf(item)])
    }
}
