import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property string systemLocale: qsTr("Detecting…")
    property string timezone: qsTr("Detecting…")
    property string ntpState: ""
    property string keyboardLayout: ""

    function refreshSystemRegion(): void {
        localeProc.running = timeProc.running = true;
    }

    // Temperature units (index 0 = Celsius, 1 = Fahrenheit — matches Weather.formatTemp)
    readonly property list<MenuItem> tempItems: [
        MenuItem {
            text: "°C"
        },
        MenuItem {
            text: "°F"
        }
    ]

    // Clock format (index 0 = 24-hour, 1 = 12-hour — matches Time.useTwelveHourClock)
    readonly property list<MenuItem> clockItems: [
        MenuItem {
            text: qsTr("24-hour")
        },
        MenuItem {
            text: qsTr("12-hour")
        }
    ]

    title: qsTr("Language & region")

    Component.onCompleted: refreshSystemRegion()

    property Process localeProcess: Process {
        id: localeProc
        command: ["localectl", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const locale = text.match(/System Locale:\s*LANG=([^\s]+)/);
                const layout = text.match(/X11 Layout:\s*([^\s]+)/);
                root.systemLocale = locale?.[1] ?? Qt.locale().name;
                root.keyboardLayout = layout?.[1] ?? "";
            }
        }
    }

    property Process timeProcess: Process {
        id: timeProc
        command: ["timedatectl", "show", "--property=Timezone", "--property=NTP", "--property=NTPSynchronized"]
        stdout: StdioCollector {
            onStreamFinished: {
                const zone = text.match(/Timezone=(.*)/);
                const ntp = text.match(/NTP=(.*)/);
                const synced = text.match(/NTPSynchronized=(.*)/);
                root.timezone = zone?.[1] || qsTr("Unknown");
                root.ntpState = ntp?.[1] === "yes" ? (synced?.[1] === "yes" ? qsTr("Synchronized") : qsTr("Enabled")) : qsTr("Disabled");
            }
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Language
        SectionHeader {
            first: true
            text: qsTr("Language")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: localeLayout.implicitHeight + localeLayout.anchors.margins * 2

            RowLayout {
                id: localeLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("System language")
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Shell and applications follow the system locale")
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    text: root.systemLocale
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.medium

            IconTextButton {
                Layout.fillWidth: true
                icon: "translate"
                text: qsTr("Language & formats")
                type: ButtonBase.Filled
                onClicked: Quickshell.execDetached(["kcmshell6", "kcm_regionandlang"])
            }
            IconTextButton {
                Layout.fillWidth: true
                icon: "keyboard"
                text: qsTr("Keyboard layouts")
                type: IconTextButton.Tonal
                onClicked: Quickshell.execDetached(["kcmshell6", "kcm_keyboard"])
            }
        }

        InfoRow {
            Layout.topMargin: Tokens.spacing.small
            first: true
            last: true
            icon: "keyboard_alt"
            label: qsTr("Active keyboard layout")
            value: root.keyboardLayout || qsTr("System default")
        }

        // Weather
        SectionHeader {
            text: qsTr("Weather")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: locationLayout.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: locationLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledTextField {
                    id: weatherLocation

                    Layout.fillWidth: true
                    placeholderText: qsTr("City or latitude,longitude")
                    leadingIcon: "location_on"
                    text: GlobalConfig.services.weatherLocation
                    emptyIsValid: true
                    supportingText: qsTr("Leave empty to detect your location automatically")
                    onAccepted: saveLocation()

                    function saveLocation(): void {
                        GlobalConfig.services.weatherLocation = text.trim();
                        Weather.reload();
                        focus = false;
                    }
                }

                IconTextButton {
                    Layout.alignment: Qt.AlignTop
                    icon: "save"
                    text: qsTr("Save")
                    type: ButtonBase.Filled
                    onClicked: weatherLocation.saveLocation()
                }
            }
        }

        // Units
        SectionHeader {
            text: qsTr("Units")
        }

        SelectRow {
            first: true
            label: qsTr("Temperature")
            subtext: qsTr("Units for weather temperatures")
            menuItems: root.tempItems
            active: root.tempItems[GlobalConfig.services.useFahrenheit ? 1 : 0]
            onSelected: item => GlobalConfig.services.useFahrenheit = root.tempItems.indexOf(item) === 1
        }

        SelectRow {
            last: true
            label: qsTr("System temperatures")
            subtext: qsTr("Units for CPU and GPU temperatures")
            menuItems: root.tempItems
            active: root.tempItems[GlobalConfig.services.useFahrenheitPerformance ? 1 : 0]
            onSelected: item => GlobalConfig.services.useFahrenheitPerformance = root.tempItems.indexOf(item) === 1
        }

        // Time & date
        SectionHeader {
            text: qsTr("Time & date")
        }

        SelectRow {
            first: true
            label: qsTr("Clock format")
            subtext: qsTr("How times are shown across the shell")
            menuItems: root.clockItems
            active: root.clockItems[GlobalConfig.services.useTwelveHourClock ? 1 : 0]
            onSelected: item => GlobalConfig.services.useTwelveHourClock = root.clockItems.indexOf(item) === 1
        }

        InfoRow {
            icon: "public"
            label: qsTr("Time zone")
            value: root.timezone
        }

        InfoRow {
            last: true
            icon: "sync"
            label: qsTr("Network time")
            value: root.ntpState
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.medium
            IconTextButton {
                icon: "schedule"
                text: qsTr("Date & time settings")
                type: ButtonBase.Filled
                onClicked: Quickshell.execDetached(["kcmshell6", "kcm_clock"])
            }
            IconTextButton {
                icon: "refresh"
                text: qsTr("Refresh")
                type: IconTextButton.Tonal
                onClicked: root.refreshSystemRegion()
            }
        }
    }
}
