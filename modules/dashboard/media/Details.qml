import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    readonly property bool phoneSource: PhoneService.mediaAvailable && (PhoneService.selectedMediaSource === "phone" || !Players.active || (PhoneService.selectedMediaSource === "auto" && PhoneService.mediaPlaying && !(Players.active?.isPlaying ?? false)))
    readonly property bool hasUnknownLength: !phoneSource && (Players.active?.length ?? 0) > 2147483647

    function lengthStr(length: int): string {
        if (length < 0)
            return "-1:-1";

        const hours = Math.floor(length / 3600);
        const mins = Math.floor((length % 3600) / 60);
        const secs = Math.floor(length % 60).toString().padStart(2, "0");

        if (hours > 0)
            return `${hours}:${mins.toString().padStart(2, "0")}:${secs}`;
        return `${mins}:${secs}`;
    }

    spacing: Tokens.spacing.extraSmall

    Timer {
        running: root.visible && !root.phoneSource && (Players.active?.isPlaying ?? false)
        interval: GlobalConfig.dashboard.mediaUpdateInterval
        triggeredOnStart: true
        repeat: true
        onTriggered: Players.active?.positionChanged()
    }

    StyledText {
        Layout.fillWidth: true
        text: root.phoneSource ? PhoneService.mediaTitle : Players.active?.trackTitle ?? ""
        font: Tokens.font.title.large
        elide: Text.ElideRight
        animate: true
    }

    StyledText {
        Layout.fillWidth: true
        text: root.phoneSource ? PhoneService.mediaArtist || qsTr("Unknown artist") : Players.active?.trackArtist || qsTr("Unknown artist")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.title.medium
        elide: Text.ElideRight
        animate: true
    }

    StyledText {
        Layout.fillWidth: true
        text: root.phoneSource ? PhoneService.mediaAlbum || PhoneService.deviceName : Players.active?.trackAlbum || qsTr("Unknown album")
        color: Colours.palette.m3secondary
        font: Tokens.font.title.medium
        elide: Text.ElideRight
        animate: true
    }

    RowLayout {
        Layout.topMargin: Tokens.spacing.extraLargeIncreased
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        MaterialIcon {
            text: root.phoneSource ? "smartphone" : "computer"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.medium
        }

        StyledText {
            text: root.phoneSource ? PhoneService.deviceName : qsTr("Bilgisayar")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.large
        }

        StyledSlider {
            Layout.fillWidth: true
            value: root.phoneSource ? PhoneService.mediaVolume : Math.min(1, Audio.volume)
            interactionOnMove: false
            onInteraction: value => {
                if (root.phoneSource)
                    PhoneService.setMediaVolume(value);
                else
                    Audio.setVolume(value);
            }
        }

        StyledText {
            Layout.preferredWidth: 36
            text: `${Math.round((root.phoneSource ? PhoneService.mediaVolume : Math.min(1, Audio.volume)) * 100)}%`
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        Layout.topMargin: Tokens.spacing.large
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        TextMetrics {
            id: timeMetrics

            text: root.lengthStr(root.phoneSource ? PhoneService.mediaDuration : Players.active ? Math.max(Players.active.position, root.hasUnknownLength ? 0 : Players.active.length) : 0).replace(/[1-9]/g, "0")
            font: Tokens.font.label.medium
        }

        StyledText {
            id: positionLabel

            Layout.preferredWidth: timeMetrics.width
            text: root.lengthStr(root.phoneSource ? PhoneService.mediaPosition : Players.active?.position ?? -1)
            color: Colours.palette.m3onSurfaceVariant
            font: timeMetrics.font
            horizontalAlignment: Text.AlignHCenter
        }

        StyledSlider {
            id: positionSlider

            Layout.fillWidth: true
            value: root.phoneSource ? PhoneService.mediaPosition / (PhoneService.mediaDuration || 1) : Players.active ? Players.active.position / (Players.active.length || 1) : 0
            enabled: root.phoneSource ? PhoneService.mediaDuration > 0 : (Players.active?.canSeek ?? false) && !root.hasUnknownLength
            wavy: true
            animateWave: root.phoneSource ? PhoneService.mediaPlaying : Players.active?.isPlaying ?? false
            waveFrequency: 5
            waveDuration: 2000
            interactionOnMove: false
            onInteraction: value => {
                if (root.phoneSource) {
                    PhoneService.seekMedia(value * PhoneService.mediaDuration);
                    return;
                }
                const active = Players.active;
                if (active?.canSeek && active?.positionSupported)
                    active.position = value * active.length;
            }

            Binding {
                target: positionLabel
                property: "text"
                value: root.lengthStr(positionSlider.pos * (root.phoneSource ? PhoneService.mediaDuration : Players.active?.length ?? 0))
                when: positionSlider.dragging
            }
        }

        StyledText {
            Layout.preferredWidth: timeMetrics.width
            text: root.phoneSource ? root.lengthStr(PhoneService.mediaDuration) : root.hasUnknownLength ? "--:--" : root.lengthStr(Players.active?.length ?? -1)
            color: Colours.palette.m3onSurfaceVariant
            font: timeMetrics.font
            horizontalAlignment: Text.AlignHCenter
        }
    }

    ButtonRow {
        Layout.topMargin: Tokens.spacing.largeIncreased
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        IconButton {
            type: IconButton.Tonal
            icon: "shuffle"
            isRound: true
            shapeMorph: true
            checked: !root.phoneSource && (Players.active?.shuffle ?? false)
            font: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
            disabled: root.phoneSource || !Players.active?.shuffleSupported
            onClicked: Players.active.shuffle = !Players.active?.shuffle
            implicitWidth: Math.round(implicitHeight * 0.9)
        }

        IconButton {
            id: previousBtn

            type: IconButton.Tonal
            icon: "skip_previous"
            isRound: true
            shapeMorph: true
            font: Tokens.font.icon.large
            disabled: root.phoneSource ? !PhoneService.mediaAvailable : !Players.active?.canGoPrevious
            onClicked: root.phoneSource ? PhoneService.controlMedia("media-previous") : Players.active?.previous()
        }

        IconButton {
            id: playPauseBtn

            icon: (root.phoneSource ? PhoneService.mediaPlaying : Players.active?.isPlaying) ? "pause" : "play_arrow"
            isRound: true
            shapeMorph: true
            fillWidth: true
            checked: root.phoneSource ? PhoneService.mediaPlaying : Players.active?.isPlaying ?? false
            font: Tokens.font.icon.large
            disabled: root.phoneSource ? !PhoneService.mediaAvailable : !Players.active?.canTogglePlaying
            onClicked: root.phoneSource ? PhoneService.controlMedia("media-play-pause") : Players.active?.togglePlaying()
        }

        IconButton {
            id: nextBtn

            type: IconButton.Tonal
            icon: "skip_next"
            isRound: true
            shapeMorph: true
            font: Tokens.font.icon.large
            disabled: root.phoneSource ? !PhoneService.mediaAvailable : !Players.active?.canGoNext
            onClicked: root.phoneSource ? PhoneService.controlMedia("media-next") : Players.active?.next()
        }

        IconButton {
            type: IconButton.Tonal
            icon: Players.active?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
            isRound: true
            shapeMorph: true
            checked: !root.phoneSource && (Players.active?.loopState === MprisLoopState.Track || Players.active?.loopState === MprisLoopState.Playlist)
            font: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
            disabled: root.phoneSource || !Players.active?.loopSupported
            onClicked: {
                const state = Players.active.loopState;
                if (state === MprisLoopState.None)
                    Players.active.loopState = MprisLoopState.Track;
                else if (state === MprisLoopState.Track)
                    Players.active.loopState = MprisLoopState.Playlist;
                else
                    Players.active.loopState = MprisLoopState.None;
            }
            implicitWidth: Math.round(implicitHeight * 0.9)
        }
    }
}
