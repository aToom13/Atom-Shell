pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import M3Shapes
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.widgets
import qs.services

Item {
    id: root

    readonly property bool phoneSource: PhoneService.mediaAvailable && (PhoneService.selectedMediaSource === "phone" || !Players.active || (PhoneService.selectedMediaSource === "auto" && PhoneService.mediaPlaying && !(Players.active?.isPlaying ?? false)))
    readonly property bool playing: phoneSource ? PhoneService.mediaPlaying : Players.active?.isPlaying ?? false
    readonly property real bpm: phoneSource ? PhoneService.mediaBpm : Audio.beatTracker.bpm
    readonly property bool cavaActive: Audio.cava.values.some(value => value > 0.02)
    property real beatPhase

    readonly property real centerX: width / 2
    readonly property real centerY: height / 2
    readonly property real spacing: Tokens.spacing.medium
    readonly property real maxMagnitude: (implicitWidth - cover.implicitWidth) / 2 - spacing

    ServiceRef {
        service: root.visible && root.playing && !root.phoneSource && !GameMode.pauseVisualisers ? Audio.cava : null
    }

    ServiceRef {
        service: root.visible && root.playing && !root.phoneSource && !GameMode.pauseVisualisers ? Audio.beatTracker : null
    }

    NumberAnimation on beatPhase {
        from: 0
        to: 1
        duration: Math.round(60000 / Math.max(root.bpm || 110, 1))
        loops: Animation.Infinite
        running: root.visible && root.playing && !GameMode.pauseVisualisers
    }

    Shape {
        anchors.fill: parent
        asynchronous: true
        preferredRendererType: Shape.CurveRenderer
        data: bars.instances
    }

    Variants {
        id: bars

        model: Array.from({
            length: GameMode.pauseVisualisers ? 0 : GlobalConfig.services.visualiserBars
        }, (_, i) => i)

        ShapePath {
            id: bar

            required property int modelData
            readonly property real value: {
                if (root.playing && !root.phoneSource && root.cavaActive)
                    return Math.max(1e-2, Math.min(1, Audio.cava.values[modelData]));
                const offset = modelData / GlobalConfig.services.visualiserBars;
                const pulse = Math.max(0, Math.sin((root.beatPhase + offset * 0.22) * Math.PI * 2));
                const texture = 0.65 + 0.35 * Math.sin((root.beatPhase * 2 + offset * 3) * Math.PI * 2);
                return root.playing ? 0.08 + pulse * pulse * texture * 0.75 : 0.01;
            }

            readonly property real angle: modelData * 2 * Math.PI / GlobalConfig.services.visualiserBars
            readonly property real dist: shapeEdgeDist + value * root.maxMagnitude
            readonly property real shapeEdgeDist: {
                cover.shape.rotation; // Update when shape rotation changes
                const sDist = cover.shape.distanceAtAngle(modelData * 360 / GlobalConfig.services.visualiserBars + 90);
                return sDist + root.spacing + strokeWidth / 2;
            }
            readonly property real cos: Math.cos(angle)
            readonly property real sin: Math.sin(angle)

            asynchronous: true
            capStyle: root.Tokens.rounding.scale === 0 ? ShapePath.SquareCap : ShapePath.RoundCap
            strokeWidth: 360 / GlobalConfig.services.visualiserBars - root.Tokens.spacing.small / 4
            strokeColor: Colours.palette.m3primary

            startX: root.centerX + shapeEdgeDist * cos
            startY: root.centerY + shapeEdgeDist * sin

            PathLine {
                x: root.centerX + bar.dist * bar.cos
                y: root.centerY + bar.dist * bar.sin
            }

            Behavior on strokeColor {
                CAnim {}
            }
        }
    }

    CoverArt {
        id: cover

        anchors.centerIn: parent
        shape.shape: MaterialShape.Cookie9Sided
        implicitWidth: Tokens.sizes.dashboard.mediaCoverArtSize
        implicitHeight: Tokens.sizes.dashboard.mediaCoverArtSize
        source: root.phoneSource ? PhoneService.mediaArtUrl : Players.getArtUrl(Players.active)
        playing: root.phoneSource ? PhoneService.mediaPlaying : Players.active?.isPlaying ?? false
    }
}
