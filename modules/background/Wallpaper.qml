pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    property string source: Wallpapers.current
    property var current
    property bool completed

    function isVideo(path: string): bool {
        if (!path)
            return false;
        const lower = path.toLowerCase();
        return lower.endsWith(".mp4") || lower.endsWith(".webm") || lower.endsWith(".mkv")
            || lower.endsWith(".mov") || lower.endsWith(".m4v");
    }

    function spawn() {
        if (root.current) {
            const stale = root.current;
            root.current = null;
            stale.destroy();
        }

        if (!root.source)
            return;

        if (root.isVideo(root.source))
            root.current = videoComp.createObject(root, { source: root.source });
        else
            root.current = imgComp.createObject(root, { path: root.source });
    }

    onSourceChanged: {
        if (root.completed)
            root.spawn();
    }

    Component.onCompleted: {
        if (source)
            Qt.callLater(() => {
                root.spawn();
                root.completed = true;
            });
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && !root.source

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.largeIncreased

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(5).build()
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.large.size(28 * 2).weight(Font.Bold).build()
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Tokens.padding.extraLargeIncreased
                        implicitHeight: selectWallText.implicitHeight + Tokens.padding.small

                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: qsTr("Select a wallpaper")
                            filterLabel: qsTr("Image files")
                            filters: Images.validImageExtensions
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: dialog.open()
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: qsTr("Set it now!")
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.body.large
                        }
                    }
                }
            }
        }
    }

    Component {
        id: imgComp

        CachingImage {
            id: img

            anchors.fill: parent

            opacity: 0

            onStatusChanged: {
                if (status === Image.Ready)
                    anim.start();
            }

            Anim on opacity {
                id: anim

                type: Anim.SlowEffects
                running: false
                from: 0
                to: 1
            }

            Timer {
                running: root.current !== img && root.current?.status === Image.Ready
                interval: anim.duration
                onTriggered: img.destroy()
            }
        }
    }

    Component {
        id: videoComp

        Item {
            id: vroot

            property string source

            anchors.fill: parent

            Video {
                id: vid

                anchors.fill: parent

                source: Qt.resolvedUrl(vroot.source)
                autoPlay: true
                loops: MediaPlayer.Infinite
                muted: true
                playbackRate: 1
                fillMode: VideoOutput.PreserveAspectCrop

                Connections {
                    target: GameMode

                    function onEnabledChanged(): void {
                        if (GameMode.enabled)
                            vid.pause();
                        else
                            vid.play();
                    }
                }

                Component.onCompleted: {
                    if (GameMode.enabled)
                        vid.pause();
                }

                opacity: 0

                NumberAnimation on opacity {
                    id: fadeIn

                    running: false
                    from: 0
                    to: 1
                    duration: 600
                    easing.type: Easing.InOutQuad
                }

                onPlaybackStateChanged: {
                    if (vid.playbackState === MediaPlayer.PlayingState)
                        fadeIn.start();
                }

                Timer {
                    interval: 500
                    running: true
                    repeat: false
                    onTriggered: {
                        if (vid.visible && fadeIn.running === false)
                            fadeIn.start();
                    }
                }
            }
        }
    }
}
