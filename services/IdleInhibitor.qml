pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    property alias enabled: props.enabled
    readonly property alias enabledSince: props.enabledSince
    property real nowMs: Date.now()
    readonly property int remainingSeconds: props.enabled && props.expiresAtMs > 0
        ? Math.max(0, Math.ceil((props.expiresAtMs - nowMs) / 1000)) : -1
    readonly property bool timed: props.enabled && props.expiresAtMs > 0

    onEnabledChanged: {
        if (enabled) {
            props.enabledSince = new Date();
        } else {
            props.expiresAtMs = 0;
        }
    }

    function enableFor(minutes: int): void {
        props.expiresAtMs = Date.now() + minutes * 60 * 1000;
        if (props.enabled)
            props.enabledSince = new Date();
        props.enabled = true;
    }

    function enableIndefinitely(): void {
        props.expiresAtMs = 0;
        props.enabled = true;
    }

    function disable(): void {
        props.enabled = false;
    }

    PersistentProperties {
        id: props

        property bool enabled
        property date enabledSince
        property real expiresAtMs

        reloadableId: "idleInhibitor"
    }

    Timer {
        interval: 1000
        repeat: true
        running: props.enabled && props.expiresAtMs > 0
        onTriggered: {
            root.nowMs = Date.now();
            if (root.nowMs >= props.expiresAtMs)
                root.disable();
        }
    }

    Component.onCompleted: {
        if (props.enabled && props.expiresAtMs > 0 && Date.now() >= props.expiresAtMs)
            disable();
    }

    IdleInhibitor {
        enabled: props.enabled
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            mask: Region {}
        }
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }

        function toggle(): void {
            if (props.enabled)
                root.disable();
            else
                root.enableIndefinitely();
        }

        function enable(): void {
            root.enableIndefinitely();
        }

        function disable(): void {
            root.disable();
        }

        function enableFor(minutes: int): void {
            root.enableFor(minutes);
        }

        target: "idleInhibitor"
    }
}
