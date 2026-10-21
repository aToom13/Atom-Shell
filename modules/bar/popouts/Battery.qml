pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import qs.components
import qs.services

Column {
    id: root

    readonly property real powerWatts: BatteryEstimator.hasData ? BatteryEstimator.avgPower1Min : Math.abs(UPower.displayDevice.changeRate)
    readonly property real remainingSeconds: BatteryEstimator.estimatedSeconds > 0 ? BatteryEstimator.estimatedSeconds : (powerWatts > 0 ? Math.max(0, UPower.displayDevice.energy - UPower.displayDevice.energyFull * BatteryEstimator.reserveRatio) / powerWatts * 3600 : 0)

    spacing: Tokens.spacing.medium
    width: Math.max(Tokens.sizes.bar.batteryWidth, profiles.implicitWidth)

    StyledText {
        text: UPower.displayDevice.isLaptopBattery ? qsTr("Remaining: %1%").arg(BatteryEstimator.displayPercent) : qsTr("No battery detected")
    }

    StyledText {
        function formatSeconds(s: int, fallback: string): string {
            const day = Math.floor(s / 86400);
            const hr = Math.floor(s / 3600) % 24;
            const min = Math.floor(s / 60) % 60;

            let comps = [];
            if (day > 0)
                comps.push(`${day} days`);
            if (hr > 0)
                comps.push(`${hr} hours`);
            if (min > 0)
                comps.push(`${min} mins`);

            return comps.join(", ") || fallback;
        }

        text: UPower.displayDevice.isLaptopBattery ? qsTr("Time %1: %2").arg(UPower.onBattery ? "remaining" : "until charged").arg(UPower.onBattery ? formatSeconds(root.remainingSeconds, "Calculating...") : formatSeconds(UPower.displayDevice.timeToFull, "Fully charged!")) : (GameMode.enabled ? I18n.t("Game Mode") : I18n.t("Power profile: %1", PowerProfile.toString(PowerProfiles.profile)))
    }

    StyledText {
        text: UPower.onBattery ? qsTr("~%1W").arg(root.powerWatts.toFixed(1)) : ""
        visible: text.length > 0
    }

    StyledText {
        text: GameMode.ultraEnabled ? I18n.t("Mode: Ultra power saver") : GameMode.enabled ? I18n.t("Mode: Game mode") : I18n.t("Power profile: %1", PowerProfile.toString(PowerProfiles.profile))
    }

    Loader {
        asynchronous: true
        anchors.horizontalCenter: parent.horizontalCenter

        active: PowerProfiles.degradationReason !== PerformanceDegradationReason.None

        height: active ? ((item as Item)?.implicitHeight ?? 0) : 0

        sourceComponent: StyledRect {
            implicitWidth: child.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: child.implicitHeight + Tokens.padding.large

            color: Colours.palette.m3error
            radius: Tokens.rounding.large

            Column {
                id: child

                anchors.centerIn: parent

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -font.pointSize / 10

                        text: "warning"
                        color: Colours.palette.m3onError
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Performance Degraded")
                        color: Colours.palette.m3onError
                        font: Tokens.font.mono.builders.medium.weight(Font.Medium).build()
                    }

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -font.pointSize / 10

                        text: "warning"
                        color: Colours.palette.m3onError
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: qsTr("Reason: %1").arg(PerformanceDegradationReason.toString(PowerProfiles.degradationReason))
                    color: Colours.palette.m3onError
                }
            }
        }
    }

    StyledRect {
        id: profiles

        property string current: {
            if (GameMode.ultraEnabled)
                return ultra.icon;
            if (GameMode.enabled)
                return game.icon;
            const p = PowerProfiles.profile;
            if (p === PowerProfile.PowerSaver)
                return saver.icon;
            if (p === PowerProfile.Performance)
                return perf.icon;
            return balance.icon;
        }

        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: ultra.implicitWidth + saver.implicitWidth + balance.implicitWidth + perf.implicitWidth + game.implicitWidth + Tokens.padding.extraSmall * 2 + Tokens.spacing.largeIncreased * 4
        implicitHeight: Math.max(ultra.implicitHeight, saver.implicitHeight, balance.implicitHeight, perf.implicitHeight, game.implicitHeight) + Tokens.padding.small

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.full

        StyledRect {
            id: indicator

            color: Colours.palette.m3primary
            radius: Tokens.rounding.full
            state: profiles.current

            states: [
                State {
                    name: ultra.icon

                    Fill {
                        item: ultra
                    }
                },
                State {
                    name: saver.icon

                    Fill {
                        item: saver
                    }
                },
                State {
                    name: balance.icon

                    Fill {
                        item: balance
                    }
                },
                State {
                    name: perf.icon

                    Fill {
                        item: perf
                    }
                },
                State {
                    name: game.icon

                    Fill {
                        item: game
                    }
                }
            ]

            transitions: Transition {
                AnchorAnim {}
            }
        }

        Profile {
            id: ultra

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.extraSmall

            icon: "battery_saver"
            label: qsTr("Ultra pil tasarrufu")
            enabled: GameMode.ready && !GameMode.busy && !GameProfiles.busy
            onActivated: GameMode.setUltraEnabled(!GameMode.ultraEnabled)
        }

        Profile {
            id: saver

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: ultra.right
            anchors.leftMargin: Tokens.spacing.largeIncreased

            profile: PowerProfile.PowerSaver
            icon: "energy_savings_leaf"
            label: qsTr("Pil tasarrufu")
            enabled: GameMode.ready && !GameMode.busy
        }

        Profile {
            id: balance

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: saver.right
            anchors.leftMargin: Tokens.spacing.largeIncreased

            profile: PowerProfile.Balanced
            icon: "balance"
            label: qsTr("Dengeli")
            enabled: GameMode.ready && !GameMode.busy
        }

        Profile {
            id: perf

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: balance.right
            anchors.leftMargin: Tokens.spacing.largeIncreased

            profile: PowerProfile.Performance
            icon: "rocket_launch"
            label: qsTr("Performans")
            enabled: GameMode.ready && !GameMode.busy
        }

        Profile {
            id: game

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: perf.right
            anchors.leftMargin: Tokens.spacing.largeIncreased

            icon: "sports_esports"
            label: qsTr("Oyun modu")
            enabled: GameMode.ready && !GameMode.busy && !GameProfiles.busy
            onActivated: GameMode.setEnabled(!GameMode.enabled)
        }
    }

    component Fill: AnchorChanges {
        required property Item item

        target: indicator
        anchors.left: item.left
        anchors.right: item.right
        anchors.top: item.top
        anchors.bottom: item.bottom
    }

    component Profile: Item {
        id: control

        required property string icon
        required property string label
        property int profile: -1
        signal activated()

        function activate(): void {
            if (profile >= 0)
                GameMode.selectPowerProfile(profile);
            else
                activated();
        }

        implicitWidth: icon.implicitHeight + Tokens.padding.small
        implicitHeight: icon.implicitHeight + Tokens.padding.small

        StateLayer {
            radius: Tokens.rounding.full
            color: profiles.current === parent.icon ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            onClicked: control.activate()
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: control.label
            Accessible.checkable: true
            Accessible.checked: profiles.current === control.icon
            Accessible.onPressAction: control.activate()
            Keys.onSpacePressed: control.activate()
            Keys.onReturnPressed: control.activate()
            QQC.ToolTip.visible: containsMouse
            QQC.ToolTip.text: control.label
        }

        MaterialIcon {
            id: icon

            anchors.centerIn: parent

            text: parent.icon
            fontStyle: Tokens.font.icon.large
            color: profiles.current === text ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
            fill: profiles.current === text ? 1 : 0

            Behavior on fill {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }
}
