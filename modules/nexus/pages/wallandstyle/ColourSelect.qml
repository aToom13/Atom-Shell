import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Colours")
    isSubPage: true

    readonly property list<var> schemes: [
        ["dynamic", qsTr("Wallpaper"), "auto_awesome"],
        ["caelestia", "Atom Shell", "blur_on"],
        ["catppuccin", "Catppuccin", "coffee"],
        ["dracula", "Dracula", "dark_mode"],
        ["everforest", "Everforest", "forest"],
        ["gruvbox", "Gruvbox", "texture"],
        ["nord", "Nord", "ac_unit"],
        ["rosepine", "Rosé Pine", "local_florist"],
        ["tokyonight", "Tokyo Night", "nightlight"]
    ]

    function setScheme(name: string): void {
        Quickshell.execDetached(["caelestia", "scheme", "set", "-n", name, "--notify"]);
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Automatic theming")
        }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Follow wallpaper")
            subtext: qsTr("Automatically derive mode, palette and variant")
            checked: GlobalConfig.services.smartScheme
            onToggled: {
                GlobalConfig.services.smartScheme = checked;
                if (checked)
                    root.setScheme("dynamic");
            }
        }

        SectionHeader {
            text: qsTr("Colour scheme")
        }

        GridLayout {
            Layout.fillWidth: true
            columns: width > 520 ? 3 : 2
            rowSpacing: Tokens.spacing.medium
            columnSpacing: Tokens.spacing.medium

            Repeater {
                model: root.schemes

                delegate: IconTextButton {
                    required property var modelData

                    Layout.fillWidth: true
                    icon: modelData[2]
                    text: modelData[1]
                    type: IconTextButton.Tonal
                    horizontalPadding: Tokens.padding.large
                    verticalPadding: Tokens.padding.medium
                    onClicked: root.setScheme(modelData[0])
                }
            }
        }

        SectionHeader {
            text: qsTr("Appearance")
        }

        ToggleRow {
            first: true
            text: qsTr("Dark theme")
            subtext: qsTr("Switch without changing the active palette")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }

        ToggleRow {
            last: true
            text: qsTr("Transparency")
            subtext: qsTr("Use wallpaper-tinted translucent surfaces")
            checked: Colours.transparency.enabled
            onToggled: GlobalConfig.appearance.transparency.enabled = checked
        }
    }
}
