pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> clockPositionItems: [
        MenuItem { text: qsTr("Top left") }, MenuItem { text: qsTr("Top") }, MenuItem { text: qsTr("Top right") },
        MenuItem { text: qsTr("Left") }, MenuItem { text: qsTr("Centre") }, MenuItem { text: qsTr("Right") },
        MenuItem { text: qsTr("Bottom left") }, MenuItem { text: qsTr("Bottom") }, MenuItem { text: qsTr("Bottom right") }
    ]
    readonly property list<string> clockPositionValues: ["top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right"]

    function setUiFont(family: string): void {
        const value = family.trim();
        if (!value)
            return;
        GlobalConfig.appearance.font.headline.family = value;
        GlobalConfig.appearance.font.title.family = value;
        GlobalConfig.appearance.font.body.family = value;
        GlobalConfig.appearance.font.label.family = value;
    }

    title: qsTr("Wallpaper & style")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledClippingRect {
            id: wallWrapper

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: {
                const screen = root.nState.screen;
                return implicitHeight / screen.height * screen.width;
            }
            implicitHeight: {
                const screen = root.nState.screen;
                const cWidth = root.cappedWidth;
                return Math.min(Math.round(cWidth * 0.4), cWidth / screen.width * screen.height);
            }

            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            Loader {
                anchors.centerIn: parent
                opacity: Config.background.wallpaperEnabled ? 0 : 1
                active: opacity > 0

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Wallpaper disabled")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }

            Item {
                anchors.fill: parent
                opacity: Config.background.wallpaperEnabled ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }

                Loader {
                    id: wallIndicatorLoader

                    anchors.centerIn: parent

                    opacity: 0
                    active: opacity > 0

                    sourceComponent: StyledRect {
                        implicitWidth: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2
                        implicitHeight: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2

                        color: Colours.palette.m3primaryContainer
                        radius: Tokens.rounding.full

                        LoadingIndicator {
                            id: wallLoadingIndicator

                            anchors.centerIn: parent
                            containsIcon: true
                            implicitSize: Math.min(wallWrapper.implicitWidth, wallWrapper.implicitHeight) * 0.4
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                Timer {
                    id: wallLoadDebounceTimer

                    interval: 100
                    onTriggered: {
                        if (wallImg.status !== Image.Ready)
                            wallIndicatorLoader.opacity = 1;
                    }
                }

                FadeImage {
                    id: wallImg

                    anchors.fill: parent
                    visible: !Wallpapers.isVideo(Wallpapers.current)
                    source: visible ? Wallpapers.current : ""
                    preventInit: wallIndicatorLoader.opacity > 0
                    fadeOutAnim: Anim.DefaultEffects
                    fadeInAnim: Anim.SlowEffects

                    onSourceChanged: {
                        if (visible)
                            wallLoadDebounceTimer.restart();
                        else {
                            wallLoadDebounceTimer.stop();
                            wallIndicatorLoader.opacity = 0;
                        }
                    }

                    onStatusChanged: {
                        if (status === Image.Ready) {
                            wallLoadDebounceTimer.stop();
                            wallIndicatorLoader.opacity = 0;
                        }
                    }
                }

                Video {
                    anchors.fill: parent
                    visible: Wallpapers.isVideo(Wallpapers.current)
                    source: visible ? Qt.resolvedUrl(Wallpapers.current) : ""
                    autoPlay: visible
                    loops: MediaPlayer.Infinite
                    muted: true
                    fillMode: VideoOutput.PreserveAspectCrop
                }
            }
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "wallpaper"
                text: qsTr("Wallpapers")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                disabled: !Config.background.wallpaperEnabled
                onClicked: root.nState.openSubPage(1) // Wallpaper page
            }

            IconTextButton {
                icon: "palette"
                text: qsTr("Colours")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: root.nState.openSubPage(3) // Colours page
            }
        }

        ToggleRow {
            first: true
            text: qsTr("Display wallpaper")
            checked: Config.background.wallpaperEnabled
            onToggled: GlobalConfig.background.wallpaperEnabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            text: qsTr("Transparency")
            subtext: qsTr("Base %1, layers %2").arg(Colours.transparency.base).arg(Colours.transparency.layers)
            checked: Colours.transparency.enabled
            onToggled: GlobalConfig.appearance.transparency.enabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            text: qsTr("Dark theme")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }

        SectionHeader { text: qsTr("Shell appearance") }

        StepperRow {
            first: true
            label: qsTr("Text scale")
            subtext: qsTr("Scale fonts across the shell")
            value: Config.appearance.font.scale
            from: 0.75
            to: 2
            stepSize: 0.05
            onMoved: v => GlobalConfig.appearance.font.scale = v
        }

        StepperRow {
            label: qsTr("Rounding scale")
            value: Config.appearance.rounding.scale
            from: 0
            to: 2
            stepSize: 0.1
            onMoved: v => GlobalConfig.appearance.rounding.scale = v
        }

        StepperRow {
            label: qsTr("Spacing scale")
            value: Config.appearance.spacing.scale
            from: 0.5
            to: 2
            stepSize: 0.1
            onMoved: v => GlobalConfig.appearance.spacing.scale = v
        }

        StepperRow {
            label: qsTr("Padding scale")
            value: Config.appearance.padding.scale
            from: 0.5
            to: 2
            stepSize: 0.1
            onMoved: v => GlobalConfig.appearance.padding.scale = v
        }

        StepperRow {
            label: qsTr("Base transparency")
            value: Math.round(GlobalConfig.appearance.transparency.base * 100)
            from: 20
            to: 100
            stepSize: 5
            onMoved: v => GlobalConfig.appearance.transparency.base = v / 100
        }

        StepperRow {
            label: qsTr("Layer transparency")
            value: Math.round(GlobalConfig.appearance.transparency.layers * 100)
            from: 0
            to: 100
            stepSize: 5
            onMoved: v => GlobalConfig.appearance.transparency.layers = v / 100
        }

        StepperRow {
            last: true
            label: qsTr("Animation speed")
            subtext: qsTr("Scale shell animation durations")
            value: GlobalConfig.appearance.anim.durations.scale
            from: 0
            to: 3
            stepSize: 0.1
            onMoved: v => GlobalConfig.appearance.anim.durations.scale = v
        }

        SectionHeader { text: qsTr("Fonts") }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: fontLayout.implicitHeight + Tokens.padding.large * 2
            ColumnLayout {
                id: fontLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium
                StyledTextField {
                    Layout.fillWidth: true
                    placeholderText: qsTr("Interface font family")
                    leadingIcon: "font_download"
                    text: Config.appearance.font.body.family
                    supportingText: qsTr("Applied to headings, titles, body and labels")
                    onAccepted: root.setUiFont(text)
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium
                    StyledTextField { Layout.fillWidth: true; placeholderText: qsTr("Monospace font"); text: Config.appearance.font.mono.family; onAccepted: GlobalConfig.appearance.font.mono.family = text.trim() }
                    StyledTextField { Layout.fillWidth: true; placeholderText: qsTr("Clock font"); text: Config.appearance.font.clock; onAccepted: GlobalConfig.appearance.font.clock = text.trim() }
                    StyledTextField { Layout.fillWidth: true; placeholderText: qsTr("Workspace font"); text: Config.appearance.font.workspaces; onAccepted: GlobalConfig.appearance.font.workspaces = text.trim() }
                }
            }
        }

        SectionHeader {
            text: qsTr("Desktop clock")
        }

        ToggleRow {
            first: true
            text: qsTr("Show desktop clock")
            checked: Config.background.desktopClock.enabled
            onToggled: GlobalConfig.background.desktopClock.enabled = checked
        }

        ToggleRow {
            text: qsTr("Clock background")
            checked: Config.background.desktopClock.background.enabled
            onToggled: GlobalConfig.background.desktopClock.background.enabled = checked
        }

        ToggleRow {
            text: qsTr("Blur behind clock")
            checked: Config.background.desktopClock.background.blur
            onToggled: GlobalConfig.background.desktopClock.background.blur = checked
        }

        ToggleRow {
            text: qsTr("Clock shadow")
            checked: Config.background.desktopClock.shadow.enabled
            onToggled: GlobalConfig.background.desktopClock.shadow.enabled = checked
        }

        ToggleRow {
            text: qsTr("Invert clock colours")
            checked: Config.background.desktopClock.invertColors
            onToggled: GlobalConfig.background.desktopClock.invertColors = checked
        }

        SelectRow {
            label: qsTr("Clock position")
            menuItems: root.clockPositionItems
            active: root.clockPositionItems[Math.max(0, root.clockPositionValues.indexOf(Config.background.desktopClock.position))]
            onSelected: item => GlobalConfig.background.desktopClock.position = root.clockPositionValues[root.clockPositionItems.indexOf(item)]
        }

        StepperRow {
            label: qsTr("Clock background opacity")
            value: Math.round(Config.background.desktopClock.background.opacity * 100)
            from: 0
            to: 100
            stepSize: 5
            onMoved: v => GlobalConfig.background.desktopClock.background.opacity = v / 100
        }

        StepperRow {
            label: qsTr("Clock shadow opacity")
            value: Math.round(Config.background.desktopClock.shadow.opacity * 100)
            from: 0
            to: 100
            stepSize: 5
            onMoved: v => GlobalConfig.background.desktopClock.shadow.opacity = v / 100
        }

        StepperRow {
            label: qsTr("Clock shadow blur")
            value: Config.background.desktopClock.shadow.blur
            from: 0
            to: 100
            stepSize: 1
            onMoved: v => GlobalConfig.background.desktopClock.shadow.blur = v
        }

        StepperRow {
            last: true
            label: qsTr("Clock scale")
            value: Config.background.desktopClock.scale
            from: 0.5
            to: 2
            stepSize: 0.1
            onMoved: v => GlobalConfig.background.desktopClock.scale = v
        }

        SectionHeader {
            text: qsTr("Audio visualiser")
        }

        ToggleRow {
            first: true
            text: qsTr("Show visualiser")
            checked: Config.background.visualiser.enabled
            onToggled: GlobalConfig.background.visualiser.enabled = checked
        }

        ToggleRow {
            text: qsTr("Hide when audio stops")
            checked: Config.background.visualiser.autoHide
            onToggled: GlobalConfig.background.visualiser.autoHide = checked
        }

        ToggleRow {
            text: qsTr("Blur visualiser")
            checked: Config.background.visualiser.blur
            onToggled: GlobalConfig.background.visualiser.blur = checked
        }

        StepperRow {
            label: qsTr("Visualiser rounding")
            value: Config.background.visualiser.rounding
            from: 0
            to: 3
            stepSize: 0.1
            onMoved: v => GlobalConfig.background.visualiser.rounding = v
        }

        StepperRow {
            last: true
            label: qsTr("Visualiser spacing")
            value: Config.background.visualiser.spacing
            from: 0
            to: 3
            stepSize: 0.1
            onMoved: v => GlobalConfig.background.visualiser.spacing = v
        }
    }
}
