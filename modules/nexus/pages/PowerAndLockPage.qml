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

    readonly property list<MenuItem> idleActionItems: [
        MenuItem { text: qsTr("Lock screen"); icon: "lock" },
        MenuItem { text: qsTr("Turn displays off"); icon: "display_settings" },
        MenuItem { text: qsTr("Suspend then hibernate"); icon: "bedtime" }
    ]
    readonly property list<string> idleActionValues: ["lock", "dpms off", "suspendThenHibernate"]

    function idleActionKey(action: var): string {
        return Array.isArray(action) ? (action[0] ?? "") : (action ?? "");
    }

    function updateIdleRule(index: int, key: string, value: var): void {
        GlobalConfig.general.idle.timeouts = GlobalConfig.general.idle.timeouts.map((entry, i) => {
            const copy = {};
            for (const name in entry)
                copy[name] = entry[name];
            if (i === index)
                copy[key] = value;
            return copy;
        });
    }

    function updateIdleAction(index: int, action: string): void {
        GlobalConfig.general.idle.timeouts = GlobalConfig.general.idle.timeouts.map((entry, i) => {
            const copy = {};
            for (const name in entry)
                copy[name] = entry[name];
            if (i === index) {
                copy.idleAction = action === "suspendThenHibernate" ? [action] : action;
                copy.returnAction = action === "dpms off" ? "dpms on" : "";
            }
            return copy;
        });
    }

    function removeIdleRule(index: int): void {
        GlobalConfig.general.idle.timeouts = GlobalConfig.general.idle.timeouts.filter((entry, i) => i !== index);
    }

    function addIdleRule(): void {
        GlobalConfig.general.idle.timeouts = [...GlobalConfig.general.idle.timeouts, { timeout: 300, idleAction: "lock", enabled: true }];
    }

    function updateWarnLevel(index: int, key: string, value: var): void {
        GlobalConfig.general.battery.warnLevels = GlobalConfig.general.battery.warnLevels.map((entry, i) => {
            const copy = {};
            for (const name in entry)
                copy[name] = entry[name];
            if (i === index)
                copy[key] = value;
            return copy;
        });
    }

    title: qsTr("Power & lock")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader { first: true; text: qsTr("Lock screen") }
        ToggleRow {
            first: true
            text: qsTr("Enable lock screen")
            checked: GlobalConfig.lock.enabled
            onToggled: GlobalConfig.lock.enabled = checked
        }
        ToggleRow {
            text: qsTr("Recolour lock logo")
            subtext: qsTr("Adapt the logo to the current colour scheme")
            checked: Config.lock.recolourLogo
            onToggled: GlobalConfig.lock.recolourLogo = checked
        }
        ToggleRow {
            text: qsTr("Fingerprint authentication")
            subtext: qsTr("Use enrolled fingerprints when available")
            checked: GlobalConfig.lock.enableFprint
            onToggled: GlobalConfig.lock.enableFprint = checked
        }
        StepperRow {
            label: qsTr("Fingerprint attempts")
            value: GlobalConfig.lock.maxFprintTries
            from: 1
            to: 10
            stepSize: 1
            onMoved: v => GlobalConfig.lock.maxFprintTries = v
        }
        ToggleRow {
            text: qsTr("Howdy face authentication")
            checked: GlobalConfig.lock.enableHowdy
            onToggled: GlobalConfig.lock.enableHowdy = checked
        }
        StepperRow {
            label: qsTr("Face recognition attempts")
            value: GlobalConfig.lock.maxHowdyTries
            from: 1
            to: 10
            stepSize: 1
            onMoved: v => GlobalConfig.lock.maxHowdyTries = v
        }
        ToggleRow {
            text: qsTr("Face authentication after wake")
            checked: GlobalConfig.lock.triggerHowdyOnWake
            onToggled: GlobalConfig.lock.triggerHowdyOnWake = checked
        }
        ToggleRow {
            last: true
            text: qsTr("Hide notifications on lock screen")
            subtext: qsTr("Protect notification content while the session is locked")
            checked: Config.lock.hideNotifs
            onToggled: GlobalConfig.lock.hideNotifs = checked
        }

        SectionHeader { text: qsTr("Idle behaviour") }
        ToggleRow {
            first: true
            text: qsTr("Lock before sleep")
            checked: GlobalConfig.general.idle.lockBeforeSleep
            onToggled: GlobalConfig.general.idle.lockBeforeSleep = checked
        }
        ToggleRow {
            text: qsTr("Stay awake while audio plays")
            checked: GlobalConfig.general.idle.inhibitWhenAudio
            onToggled: GlobalConfig.general.idle.inhibitWhenAudio = checked
        }
        ToggleRow {
            last: true
            text: qsTr("Stay awake while charging")
            checked: GlobalConfig.general.idle.inhibitWhenCharging
            onToggled: GlobalConfig.general.idle.inhibitWhenCharging = checked
        }

        SectionHeader { text: qsTr("Idle timers") }

        Repeater {
            model: GlobalConfig.general.idle.timeouts
            delegate: ColumnLayout {
                id: idleRule
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                ToggleRow {
                    first: true
                    text: qsTr("Idle rule %1").arg(idleRule.index + 1)
                    subtext: qsTr("%1 after %2 seconds").arg(root.idleActionItems[Math.max(0, root.idleActionValues.indexOf(root.idleActionKey(idleRule.modelData.idleAction)))].text).arg(idleRule.modelData.timeout)
                    checked: idleRule.modelData.enabled ?? true
                    onToggled: root.updateIdleRule(idleRule.index, "enabled", checked)
                }
                StepperRow {
                    label: qsTr("Timeout")
                    subtext: qsTr("Seconds without input")
                    value: idleRule.modelData.timeout ?? 300
                    from: 30
                    to: 7200
                    stepSize: 30
                    onMoved: v => root.updateIdleRule(idleRule.index, "timeout", Math.round(v))
                }
                SelectRow {
                    label: qsTr("Action")
                    menuItems: root.idleActionItems
                    active: root.idleActionItems[Math.max(0, root.idleActionValues.indexOf(root.idleActionKey(idleRule.modelData.idleAction)))]
                    onSelected: item => root.updateIdleAction(idleRule.index, root.idleActionValues[root.idleActionItems.indexOf(item)])
                }
                ConnectedRect {
                    Layout.fillWidth: true
                    last: true
                    implicitHeight: removeIdleLayout.implicitHeight + Tokens.padding.medium * 2
                    RowLayout {
                        id: removeIdleLayout
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        anchors.leftMargin: Tokens.padding.largeIncreased
                        anchors.rightMargin: Tokens.padding.largeIncreased
                        StyledText { Layout.fillWidth: true; text: qsTr("Remove this idle rule"); color: Colours.palette.m3outline; font: Tokens.font.body.small }
                        IconButton { icon: "delete"; type: IconButton.Text; onClicked: root.removeIdleRule(idleRule.index) }
                    }
                }
            }
        }

        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium
            icon: "add"
            text: qsTr("Add idle rule")
            type: IconTextButton.Tonal
            onClicked: root.addIdleRule()
        }

        SectionHeader { text: qsTr("Battery") }
        StepperRow {
            first: true
            last: GlobalConfig.general.battery.warnLevels.length === 0
            label: qsTr("Critical battery level")
            subtext: qsTr("Percentage that triggers the critical warning")
            value: GlobalConfig.general.battery.criticalLevel
            from: 2
            to: 25
            stepSize: 1
            onMoved: v => GlobalConfig.general.battery.criticalLevel = v
        }

        Repeater {
            model: GlobalConfig.general.battery.warnLevels
            delegate: StepperRow {
                required property var modelData
                required property int index
                first: false
                last: index === GlobalConfig.general.battery.warnLevels.length - 1
                label: modelData.title ?? qsTr("Battery warning %1").arg(index + 1)
                subtext: modelData.critical ? qsTr("Critical warning") : qsTr("Low-battery notification")
                value: modelData.level ?? 10
                from: 1
                to: 50
                stepSize: 1
                onMoved: v => root.updateWarnLevel(index, "level", Math.round(v))
            }
        }

        SectionHeader { text: qsTr("On-screen display") }
        ToggleRow {
            first: true
            text: qsTr("Enable OSD")
            checked: Config.osd.enabled
            onToggled: GlobalConfig.osd.enabled = checked
        }
        ToggleRow {
            text: qsTr("Brightness OSD")
            checked: Config.osd.enableBrightness
            onToggled: GlobalConfig.osd.enableBrightness = checked
        }
        ToggleRow {
            text: qsTr("Microphone OSD")
            checked: Config.osd.enableMicrophone
            onToggled: GlobalConfig.osd.enableMicrophone = checked
        }
        StepperRow {
            last: true
            label: qsTr("Hide delay")
            subtext: qsTr("Time before the OSD disappears (ms)")
            value: Config.osd.hideDelay
            from: 250
            to: 5000
            stepSize: 250
            onMoved: v => GlobalConfig.osd.hideDelay = v
        }

        SectionHeader { text: qsTr("Session menu") }
        ToggleRow {
            first: true
            text: qsTr("Enable session menu")
            checked: Config.session.enabled
            onToggled: GlobalConfig.session.enabled = checked
        }
        ToggleRow {
            text: qsTr("Vim-style navigation")
            checked: Config.session.vimKeybinds
            onToggled: GlobalConfig.session.vimKeybinds = checked
        }
        StepperRow {
            label: qsTr("Session menu drag threshold")
            value: Config.session.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.session.dragThreshold = Math.round(v)
        }
        StepperRow {
            last: true
            label: qsTr("Session animation speed")
            value: Config.general.sessionGifSpeed
            from: 0.1
            to: 2
            stepSize: 0.1
            onMoved: v => GlobalConfig.general.sessionGifSpeed = v
        }
    }
}
