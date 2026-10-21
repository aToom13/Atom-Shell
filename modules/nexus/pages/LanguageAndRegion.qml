import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property string systemLocale: qsTr("Detecting…")
    property string timezone: qsTr("Detecting…")
    property string ntpState: ""
    property string keyboardLayout: ""
    property string keyboardVariant: ""
    property list<string> locales: []
    property bool ntpEnabled
    property string regionError
    readonly property list<string> regionHelper: ["python3", Paths.toLocalFile(Qt.resolvedUrl("../../../utils/region.py"))]

    function changeRegion(args: var): void {
        if (regionAction.running) return;
        regionError = "";
        regionAction.command = [...regionHelper, ...args];
        regionAction.running = true;
    }

    function refreshSystemRegion(): void {
        localeProc.running = timeProc.running = true;
        choices.running = true;
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

    // Shell interface language (0 = Auto/System, 1 = Türkçe, 2 = English)
    readonly property list<MenuItem> languageItems: [
        MenuItem {
            text: qsTr("System default")
        },
        MenuItem {
            text: "Türkçe"
        },
        MenuItem {
            text: "English"
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
                root.systemLocale = locale?.[1] ?? Qt.locale().name;
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
                root.ntpEnabled = ntp?.[1] === "yes";
            }
        }
    }

    property Process choiceProcess: Process {
        id: choices
        command: [...root.regionHelper, "choices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.locales = data.locales;
                    root.keyboardLayout = data.layout;
                    root.keyboardVariant = data.variant;
                } catch (error) { root.regionError = qsTr("Could not read regional settings"); }
            }
        }
    }
    property Process regionActionProcess: Process {
        id: regionAction
        stderr: StdioCollector { id: regionActionError }
        onExited: code => {
            if (code) root.regionError = regionActionError.text.trim();
            else Toaster.toast(qsTr("Settings saved"), command[2] === "locale" ? qsTr("Language changes apply after signing in again") : qsTr("Changes applied"), "check");
            root.refreshSystemRegion();
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledText { Layout.fillWidth: true; visible: root.regionError !== ""; text: root.regionError; wrapMode: Text.WordWrap; color: Colours.palette.m3error }

        // Language
        SectionHeader {
            first: true
            text: qsTr("Language")
        }

        SelectRow {
            first: true
            label: qsTr("Shell interface language")
            subtext: qsTr("Language used for desktop UI components")
            menuItems: root.languageItems
            active: root.languageItems[I18n.language === "tr" ? 1 : (I18n.language === "en" ? 2 : 0)]
            onSelected: item => {
                const idx = root.languageItems.indexOf(item);
                const code = idx === 1 ? "tr" : (idx === 2 ? "en" : "auto");
                I18n.setLanguage(code);
                Toaster.toast(qsTr("Settings saved"), qsTr("Changes applied"), "translate");
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
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

            ComboBox {
                id: localeChoice
                Layout.fillWidth: true
                model: root.locales
                currentIndex: root.locales.indexOf(root.systemLocale)
                Accessible.name: qsTr("Installed system language")
            }
            IconTextButton {
                Layout.fillWidth: true
                icon: "translate"
                text: qsTr("Apply language")
                type: ButtonBase.Filled
                disabled: regionAction.running || localeChoice.currentIndex < 0
                onClicked: root.changeRegion(["locale", localeChoice.currentText])
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

        RowLayout {
            Layout.fillWidth: true
            StyledTextField { id: layoutInput; Layout.fillWidth: true; text: root.keyboardLayout; placeholderText: qsTr("Hyprland keyboard layouts"); supportingText: qsTr("Layout codes, e.g. tr or tr,us (up to 4)") }
            StyledTextField { id: variantInput; Layout.fillWidth: true; text: root.keyboardVariant; placeholderText: qsTr("Variants (optional)"); supportingText: qsTr("Example: f for Turkish F; empty uses the default") }
        }
        IconTextButton {
            Layout.alignment: Qt.AlignRight
            icon: "keyboard"
            text: qsTr("Apply keyboard layout")
            disabled: regionAction.running || !layoutInput.text.trim()
            onClicked: root.changeRegion(["keyboard", layoutInput.text.trim(), variantInput.text.trim()])
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

        StyledTextField {
            id: zoneInput
            Layout.fillWidth: true
            text: root.timezone
            placeholderText: qsTr("Time zone")
            supportingText: qsTr("Example: Europe/Tirane or Europe/Istanbul")
        }
        ToggleRow {
            first: true
            last: true
            text: qsTr("Automatic network time")
            checked: root.ntpEnabled
            disabled: regionAction.running
            onToggled: root.changeRegion(["ntp", checked ? "true" : "false"])
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.medium
            IconTextButton {
                icon: "schedule"
                text: qsTr("Apply time zone")
                type: ButtonBase.Filled
                disabled: regionAction.running || !zoneInput.text.trim()
                onClicked: root.changeRegion(["timezone", zoneInput.text.trim()])
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
