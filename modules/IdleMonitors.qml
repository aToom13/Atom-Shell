pragma ComponentBehavior: Bound

import "lock"
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.Services
import qs.services

Scope {
    id: root

    required property Lock lock
    readonly property bool hasPlayer: Players.list.some(p => p.isPlaying)
    readonly property bool isCharging: !UPower.onBattery
    property bool ultraScreenOff: false
    readonly property bool enabled: {
        if (GameMode.inhibitIdle)
            return false;
        if (GlobalConfig.general.idle.inhibitWhenAudio && hasPlayer)
            return false;
        if (GlobalConfig.general.idle.inhibitWhenCharging && isCharging)
            return false;
        return true;
    }

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        // ponytail: keep locking/DPMS; defer automatic sleep during the pilot.
        if (ShellState.shellRoot?.hibernation?.pilot
            && /\b(suspend|hibernate|suspendThenHibernate|suspend-then-hibernate|hybridSleep|hybrid-sleep)\b/.test(Array.isArray(action) ? action.join(" ") : action))
            return;

        if (action === "lock")
            lock.lock.locked = true;
        else if (action === "unlock")
            lock.lock.locked = false;
        else if (typeof action === "string")
            Hypr.dispatch(Hypr.usingLua && ["dpms off", "dpms on"].includes(action) ? `hl.dsp.dpms({ action = "${action === "dpms off" ? "disable" : "enable"}" })` : action);
        else if (!SessionManager.exec(action))
            Quickshell.execDetached(action);
    }

    Connections {
        function onAboutToSleep(): void {
            if (GlobalConfig.general.idle.lockBeforeSleep)
                root.lock.lock.locked = true;
        }

        function onLockRequested(): void {
            root.lock.lock.locked = true;
        }

        function onUnlockRequested(): void {
            root.lock.lock.unlock();
        }

        target: SessionManager
    }

    Connections {
        target: GameMode
        function onUltraEnabledChanged(): void {
            if (!GameMode.ultraEnabled && root.ultraScreenOff) {
                root.handleIdleAction("dpms on");
                root.ultraScreenOff = false;
            }
        }
    }

    IdleMonitor {
        enabled: GameMode.ultraEnabled
        timeout: 30
        respectInhibitors: true
        onIsIdleChanged: GameMode.setUltraDimmed(isIdle)
    }

    IdleMonitor {
        enabled: GameMode.ultraEnabled
        timeout: 90
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle && GameMode.ultraEnabled) {
                root.ultraScreenOff = true;
                root.handleIdleAction("dpms off");
            } else if (root.ultraScreenOff) {
                root.handleIdleAction("dpms on");
                root.ultraScreenOff = false;
            }
        }
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts

        IdleMonitor {
            required property var modelData

            enabled: {
                if (!root.enabled || !(modelData.enabled ?? true))
                    return false;
                if (modelData.inhibitWhenAudio && root.hasPlayer)
                    return false;
                if (modelData.inhibitWhenCharging && root.isCharging)
                    return false;
                const action = Array.isArray(modelData.idleAction) ? modelData.idleAction[0] : modelData.idleAction;
                if (GameMode.ultraEnabled && (root.hasPlayer || PhoneService.mediaPlaying)
                    && ["suspend", "hibernate", "suspendThenHibernate", "suspend-then-hibernate", "hybridSleep"].includes(action))
                    return false;
                return true;
            }
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }
}
