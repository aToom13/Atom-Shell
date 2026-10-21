pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property bool sidebarOrSessionVisible

    property bool hovered
    property bool expanded
    property bool keyboardArmed
    readonly property var mixer: content.item?.mixer ?? null
    readonly property string keyMode: expanded ? "mixer" : keyboardArmed ? "armed" : "off"
    readonly property Brightness.Monitor monitor: Brightness.getMonitorForScreen(root.screen)
    readonly property bool shouldBeActive: screenState.osd && !screenState.session && Config.osd.enabled && !(screenState.utilities && Config.utilities.enabled)
    property real offsetScale: shouldBeActive ? 0 : 1
    property real sidebarOffset: sidebarOrSessionVisible ? 12 : 0

    property real volume
    property bool muted
    property real sourceVolume
    property bool sourceMuted
    property real brightness

    function show(): void {
        screenState.osd = true;
        timer.restart();
    }

    function showAudio(): void {
        show();
        if (!expanded && shouldBeActive && ShellState.forActive() === screenState)
            keyboardArmed = true;
    }

    function openMixer(): void {
        if (!Config.osd.enabled || screenState.session || screenState.utilities)
            return;
        screenState.osd = true;
        expanded = true;
        keyboardArmed = false;
        timer.stop();
        mixer?.forceActiveFocus();
    }

    function closeMixer(): void {
        expanded = false;
        keyboardArmed = false;
        screenState.osd = false;
    }

    function adjustSelected(direction: int): void { mixer?.adjustVolume(direction); }
    function muteSelected(): void { mixer?.toggleMute(); }

    function syncKeys(): void {
        if (keyProcess.running)
            return;
        keyProcess.mode = keyMode;
        keyProcess.command = ["hyprctl", "eval", "if _G.caelestiaAudioKeys then _G.caelestiaAudioKeys('" + keyMode + "') end"];
        keyProcess.running = true;
    }

    onKeyModeChanged: syncKeys()
    onShouldBeActiveChanged: {
        if (!shouldBeActive) {
            keyboardArmed = false;
            expanded = false;
        }
    }
    Component.onDestruction: {
        if (keyMode !== "off")
            Quickshell.execDetached(["hyprctl", "eval", "if _G.caelestiaAudioKeys then _G.caelestiaAudioKeys('off') end"]);
    }

    Process {
        id: keyProcess
        property string mode
        onExited: { if (mode !== root.keyMode) root.syncKeys(); }
    }

    Timer {
        interval: 650
        repeat: true
        running: root.keyMode !== "off"
        onTriggered: root.syncKeys()
    }

    Connections {
        target: root.screenState
        function onOsdChanged(): void {
            if (!root.screenState.osd) {
                root.expanded = false;
                root.keyboardArmed = false;
            }
        }
    }

    Component.onCompleted: {
        volume = Audio.volume;
        muted = Audio.muted;
        sourceVolume = Audio.sourceVolume;
        sourceMuted = Audio.sourceMuted;
        brightness = root.monitor?.brightness ?? 0;
    }

    visible: offsetScale < 1
    clip: true
    anchors.rightMargin: (-implicitWidth - 5 - sidebarOffset) * offsetScale
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }
    Behavior on implicitWidth { Anim { type: Anim.Emphasized } }
    Behavior on implicitHeight { Anim { type: Anim.Emphasized } }

    Connections {
        function onMutedChanged(): void {
            root.showAudio();
            root.muted = Audio.muted;
        }

        function onVolumeChanged(): void {
            root.showAudio();
            root.volume = Audio.volume;
        }

        function onSourceMutedChanged(): void {
            root.show();
            root.sourceMuted = Audio.sourceMuted;
        }

        function onSourceVolumeChanged(): void {
            root.show();
            root.sourceVolume = Audio.sourceVolume;
        }

        target: Audio
    }

    Connections {
        function onBrightnessChanged(): void {
            root.show();
            root.brightness = root.monitor?.brightness ?? 0;
        }

        target: root.monitor
    }

    Timer {
        id: timer

        interval: root.Config.osd.hideDelay
        onTriggered: {
            if (!root.hovered && !root.expanded)
                root.screenState.osd = false;
        }
    }

    Loader {
        id: content

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right

        asynchronous: true
        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            controller: root
            monitor: root.monitor
            screenState: root.screenState
            volume: root.volume
            muted: root.muted
            sourceVolume: root.sourceVolume
            sourceMuted: root.sourceMuted
            brightness: root.brightness
        }
    }
}
