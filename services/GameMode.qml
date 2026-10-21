pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import qs.services

Singleton {
    id: root

    readonly property bool enabled: !!session.active && (session.mode ?? "game") === "game"
    readonly property bool ultraEnabled: !!session.active && session.mode === "ultra"
    readonly property bool busy: worker.running || startingInhibitor
    property bool ready: false
    property var settings: ({})
    property var session: ({ active: false })
    readonly property var activeSettings: session.settings ?? settings
    readonly property bool disableBlur: !!session.active && !!activeSettings.disableShellBlur
    readonly property bool disableShadows: !!session.active && !!activeSettings.disableShellShadows
    readonly property bool reduceAnimations: !!session.active && !!activeSettings.disableShellAnimations
    readonly property bool opaqueWindows: !!session.active && !!activeSettings.opaqueWindows
    readonly property bool opaqueShell: !!session.active && !!activeSettings.opaqueShell
    readonly property bool pauseWallpaper: !!session.active && !!activeSettings.pauseWallpaper
    readonly property bool pauseVisualisers: !!session.active && !!activeSettings.pauseVisualisers
    readonly property bool pauseMediaArtwork: !!session.active && !!activeSettings.pauseMediaArtwork
    readonly property bool pauseMediaShapes: !!session.active && !!activeSettings.pauseMediaShapes
    readonly property bool hideDesktopClock: !!session.active && !!activeSettings.hideDesktopClock
    readonly property bool muteToasts: enabled && !!activeSettings.muteToasts
    readonly property bool inhibitIdle: enabled && !!activeSettings.inhibitIdle
    readonly property bool inhibitSleep: enabled && !!activeSettings.inhibitSleep
    readonly property bool muteNotifications: enabled && !!activeSettings.muteNotifications
    readonly property string error: lastError || inhibitorError
    property string lastError
    property string inhibitorError
    property string actualProfile
    property string profileName
    property string action
    property int pendingPowerProfile: -1
    property var result
    property var hardware: ({})
    property bool ultraDimmedWanted: false
    property bool startingInhibitor: false
    property bool inhibitorReady: false
    property bool enablingAfterInhibitor: false
    property bool stoppingInhibitor: false
    property bool reloadPending: false
    readonly property string helper: Qt.resolvedUrl("../utils/game_mode.py").toString().replace("file://", "")

    function run(action, argument): void {
        if (worker.running)
            return;
        root.action = action;
        root.result = null;
        worker.exec(["/usr/bin/python3", helper, action, argument ?? ""]);
    }

    function startInhibitor(enableAfter: bool): void {
        enablingAfterInhibitor = enableAfter;
        startingInhibitor = true;
        stoppingInhibitor = false;
        inhibitorError = "";
        inhibitor.running = true;
        inhibitorTimeout.restart();
    }

    function stopInhibitor(): void {
        stoppingInhibitor = true;
        startingInhibitor = false;
        inhibitorReady = false;
        inhibitorTimeout.stop();
        inhibitor.running = false;
    }

    function setEnabled(value: bool): void {
        if (!ready || busy || value === enabled)
            return;
        lastError = "";
        inhibitorError = "";
        if (value && settings.inhibitSleep)
            startInhibitor(true);
        else
            run(value ? "enable" : "disable", String(Notifs.dnd));
    }

    function setUltraEnabled(value: bool): void {
        if (!ready || busy || value === ultraEnabled)
            return;
        lastError = "";
        run(value ? "enable-ultra" : "disable", String(Notifs.dnd));
    }

    function setUltraDimmed(value: bool): void {
        ultraDimmedWanted = value;
        if (ultraEnabled && !busy)
            run(value ? "dim" : "undim");
    }

    function configure(key: string, value: var): void {
        if (!ready || busy || enabled)
            return;
        const change = {};
        change[key] = value;
        run("configure", JSON.stringify(change));
    }

    function selectPowerProfile(profile: int): void {
        if (!ready || busy || ![PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance].includes(profile))
            return;
        if (!session.active) {
            PowerProfiles.profile = profile;
            return;
        }
        pendingPowerProfile = profile;
        run("disable", String(Notifs.dnd));
    }

    function finish(exitCode: int): void {
        const requestedProfile = pendingPowerProfile;
        pendingPowerProfile = -1;
        const data = result;
        const previous = session;
        if (!data || !data.session) {
            lastError = data?.error || qsTr("Game Mode could not read its state (exit %1)").arg(exitCode);
            if (!enabled)
                stopInhibitor();
            Toaster.toast(qsTr("Game Mode error"), lastError, "error", Toast.Error);
            return;
        }
        settings = data.settings;
        session = data.session;
        hardware = data.hardware ?? ({});
        actualProfile = data.actualProfile;
        profileName = data.profileName ?? "";
        lastError = data.error || "";
        ready = true;
        if (enabled && !!activeSettings.muteNotifications)
            Notifs.dnd = true;
        else if (previous.active && !enabled && previous.settings.muteNotifications)
            Notifs.dnd = previous.previousDnd;

        if (!enabled)
            stopInhibitor();
        else if (inhibitSleep && !inhibitor.running && !inhibitorError)
            startInhibitor(false);

        if (action === "disable" && data.ok && !enabled && requestedProfile >= 0)
            PowerProfiles.profile = requestedProfile;

        if (!data.ok && action !== "status")
            Toaster.toast(qsTr("Game Mode error"), lastError, "error", Toast.Error);
        else if (data.ok && !root.error && (action === "enable-ultra" || (action === "disable" && previous.mode === "ultra")))
            Toaster.toast(ultraEnabled ? I18n.t("Ultra power saver enabled") : I18n.t("Ultra power saver disabled"), ultraEnabled ? I18n.t("Battery saving settings applied") : I18n.t("Previous settings restored"), "battery_saver");
        else if (data.ok && !root.error && (!inhibitSleep || inhibitorReady) && ["enable", "disable"].includes(action) && GlobalConfig.utilities.toasts.gameModeChanged)
            Toaster.toast(enabled ? qsTr("Game mode enabled") : qsTr("Game mode disabled"), enabled ? qsTr("Selected optimisations applied") : qsTr("Previous settings restored"), "gamepad");

        if (!ultraEnabled)
            ultraDimmedWanted = false;
        if (ultraEnabled && data.ok && !!hardware.dimmed !== ultraDimmedWanted)
            Qt.callLater(() => root.run(root.ultraDimmedWanted ? "dim" : "undim"));
        if (["enable-ultra", "dim", "undim"].includes(action) || (action === "disable" && previous.mode === "ultra")) {
            for (const monitor of Brightness.monitors) {
                if (!monitor.isDdc && !monitor.isAppleDisplay)
                    monitor.initBrightness();
            }
        }
        if (action === "status" && session.active && !previous.active)
            reloadPending = true;
        if (reloadPending && session.active) {
            reloadPending = false;
            Qt.callLater(() => root.run("reapply"));
        }
    }

    Component.onCompleted: run("status")

    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.result = JSON.parse(text); }
                catch (error) { root.result = { error: String(error) }; }
            }
        }
        stderr: StdioCollector {}
        onExited: exitCode => Qt.callLater(() => root.finish(exitCode))
    }

    Process {
        id: inhibitor
        command: ["systemd-inhibit", "--what=idle:sleep", "--mode=block", "--who=Caelestia Game Mode", "--why=Game Mode is active", "/usr/bin/python3", "-u", "-c", "import signal; print('ready', flush=True); signal.pause()"]
        stdout: SplitParser {
            onRead: line => {
                if (line.trim() !== "ready")
                    return;
                root.inhibitorReady = true;
                root.startingInhibitor = false;
                inhibitorTimeout.stop();
                if (root.enablingAfterInhibitor)
                    root.run("enable", String(Notifs.dnd));
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() && !root.stoppingInhibitor)
                    root.inhibitorError = text.trim();
            }
        }
        onExited: {
            root.startingInhibitor = false;
            root.inhibitorReady = false;
            inhibitorTimeout.stop();
            if (!root.stoppingInhibitor) {
                root.inhibitorError = root.inhibitorError || qsTr("Sleep inhibition failed. Game Mode protection is incomplete.");
                Toaster.toast(qsTr("Game Mode error"), root.inhibitorError, "error", Toast.Error);
            }
        }
    }

    Timer {
        id: inhibitorTimeout
        interval: 8000
        onTriggered: {
            root.inhibitorError = qsTr("Timed out while preventing sleep. Game Mode was not enabled.");
            root.stopInhibitor();
            Toaster.toast(qsTr("Game Mode error"), root.inhibitorError, "error", Toast.Error);
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: !!root.session.active
        onTriggered: {
            if (!root.busy)
                root.run("status");
        }
    }

    Connections {
        target: Hypr
        function onConfigReloaded(): void {
            if (!root.session.active)
                return;
            if (root.busy)
                root.reloadPending = true;
            else
                root.run("reapply");
        }
    }

    Connections {
        target: PowerProfiles
        function onProfileChanged(): void {
            if (root.ultraEnabled && !root.busy && PowerProfiles.profile !== PowerProfile.PowerSaver)
                root.setUltraEnabled(false);
        }
    }

    Connections {
        target: UPower
        function onOnBatteryChanged(): void {
            if (root.ultraEnabled)
                powerSourceDelay.restart();
        }
    }

    Timer {
        id: powerSourceDelay
        interval: 1500
        onTriggered: {
            if (root.ultraEnabled && !root.busy) {
                if (PowerProfiles.profile === PowerProfile.PowerSaver)
                    root.run("reapply");
                else
                    root.setUltraEnabled(false);
            }
        }
    }

    IpcHandler {
        target: "gameMode"
        function isEnabled(): bool { return root.enabled; }
        function toggle(): void { root.setEnabled(!root.enabled); }
        function enable(): void { root.setEnabled(true); }
        function disable(): void { root.setEnabled(false); }
        function configure(key: string, value: bool): void { root.configure(key, value); }
        function configureChoice(key: string, value: string): void { root.configure(key, value); }
        function refresh(): void { if (!root.busy) root.run("status"); }
        function status(): string {
            return JSON.stringify({ enabled: root.enabled, ultraEnabled: root.ultraEnabled, busy: root.busy, ready: root.ready, error: root.error, actualProfile: root.actualProfile, hardware: root.hardware, sleepInhibited: root.inhibitorReady, settings: root.settings, session: root.session, dnd: Notifs.dnd, notificationPopupsAllowed: Notifs.shouldShowPopup(), manualIdleInhibitor: IdleInhibitor.enabled, effectiveIdleInhibitor: IdleInhibitor.effectiveEnabled, idleExpiresAt: IdleInhibitor.timed ? IdleInhibitor.remainingSeconds : -1, shellTransparency: Colours.transparency.enabled, pauseWallpaper: root.pauseWallpaper, pauseVisualisers: root.pauseVisualisers, disableBlur: root.disableBlur });
        }
    }

    IpcHandler {
        target: "ultraMode"
        function enable(): void { root.setUltraEnabled(true); }
        function disable(): void { root.setUltraEnabled(false); }
        function toggle(): void { root.setUltraEnabled(!root.ultraEnabled); }
        function dim(value: bool): void { root.setUltraDimmed(value); }
        function status(): string { return JSON.stringify({ enabled: root.ultraEnabled, busy: root.busy, ready: root.ready, error: root.error, hardware: root.hardware }); }
    }
}
