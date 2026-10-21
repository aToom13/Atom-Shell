import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Caelestia.Services
import qs.services

Scope {
    id: root

    // ponytail: idle sleep remains deferred while low-battery hibernation is enabled.
    readonly property bool pilot: true
    property bool armed: true
    property bool policyEnabled: true
    property real promptPercentage: 5
    property real reservePercentage: 0
    property int reserveCountdownSeconds: 10
    property bool prompted: false
    property bool forcing: false
    property bool forceRequested: false
    property bool dialogVisible: false
    property string dialogStage: ""
    property int dialogCountdown: 0
    property bool dialogPreviewOnly: false
    property var sessionLock: null
    property bool onBattery: UPower.onBattery
    property bool batteryAvailable: UPower.displayDevice.ready && UPower.displayDevice.isPresent
    property real measuredBatteryPercentage: UPower.displayDevice.percentage * 100
    readonly property real batteryPercentage: displayPercentageAt(measuredBatteryPercentage / 100)
    property string availability: "na"
    property string error: ""
    property string phase: "idle"
    property bool requested: false
    readonly property bool busy: phase !== "idle" || query.running || power.running
    readonly property bool powerReady: batteryAvailable && Number.isFinite(measuredBatteryPercentage)
        && measuredBatteryPercentage >= 0 && measuredBatteryPercentage <= 100
    readonly property bool supported: availability === "yes" || availability === "challenge"
    signal dialogActionPreviewed(string stage)
    readonly property string reason: {
        if (error) return error;
        if (!armed) return I18n.t("Pilot: awaiting normal boot test.");
        if (!powerReady) return I18n.t("Could not get valid battery measurement.");
        if (!supported) return I18n.t("System does not support hibernation or disk swap is not ready.");
        if (availability === "challenge") return I18n.t("Hibernate · authentication may be required.");
        return I18n.t("Hibernate");
    }
    // Absolute production commands; replaced only by the offline check.
    property list<string> checkCommand: ["/usr/bin/busctl", "--json=short", "--timeout=4s", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "CanHibernate"]
    property list<string> powerCommand: ["/usr/bin/systemctl", "hibernate"]

    signal failed(string message)

    function displayPercentageAt(percentage: real, onBattery = UPower.onBattery): real {
        const measured = Math.max(0, Math.min(1, percentage));
        return Math.round(Math.max(0, (measured - 0.05) / 0.95) * 100);
    }

    function fail(message: string): void {
        const notify = requested;
        requested = false;
        phase = "idle";
        queryTimeout.stop();
        lockTimeout.stop();
        startTimeout.stop();
        forcing = false;
        forceRequested = false;
        closeDialog();
        error = message;
        if (notify) failed(message);
    }

    function showDialog(stage: string, previewOnly = false): void {
        if (stage !== "prompt" && stage !== "reserve")
            return;

        dialogStage = stage;
        dialogPreviewOnly = previewOnly;
        dialogVisible = true;
        dialogCountdown = stage === "reserve" ? reserveCountdownSeconds : 0;
        if (stage === "reserve")
            reserveTimer.start();
        else
            reserveTimer.stop();
    }

    function closeDialog(): void {
        reserveTimer.stop();
        dialogVisible = false;
        dialogStage = "";
        dialogCountdown = 0;
        dialogPreviewOnly = false;
    }

    function previewDialog(stage: string): void {
        if (stage !== "prompt" && stage !== "reserve")
            return;
        showDialog(stage, true);
    }

    function arm(): void {
        armed = true;
        policyEnabled = true;
        refresh();
    }

    function disarm(): void {
        armed = false;
        policyEnabled = false;
        closeDialog();
    }

    function dialogContinue(): void {
        if (!dialogVisible || dialogStage !== "prompt")
            return;
        closeDialog();
    }

    function dialogHibernate(): void {
        if (!dialogVisible)
            return;

        const stage = dialogStage;
        const previewOnly = dialogPreviewOnly;
        closeDialog();
        if (previewOnly) {
            dialogActionPreviewed(stage);
            return;
        }
        request(stage === "reserve");
    }

    function refresh(): void {
        if (busy) return;
        phase = "checking";
        query.running = true;
        queryTimeout.start();
    }

    function checkBatteryPolicy(): void {
        if (!policyEnabled || !armed || !batteryAvailable || !Number.isFinite(batteryPercentage)) return;
        if (!onBattery) {
            prompted = false;
            forcing = false;
            forceRequested = false;
            if (dialogVisible && !dialogPreviewOnly)
                closeDialog();
            return;
        }
        if (batteryPercentage <= reservePercentage) {
            if (!forcing && !forceRequested) {
                forceRequested = true;
                if (dialogVisible && dialogStage === "reserve" && !dialogPreviewOnly)
                    return;
                showDialog("reserve");
            }
            return;
        }
        if (batteryPercentage <= promptPercentage && !prompted
            && (!dialogVisible || dialogPreviewOnly)) {
            prompted = true;
            showDialog("prompt");
        }
    }

    function request(force = false): void {
        if (busy) return;
        error = "";
        if (force) forcing = true;
        requested = true;
        if (!armed || !powerReady) {
            fail(reason);
            return;
        }
        refresh();
    }

    function checked(code: int): void {
        if (phase !== "checking") return;
        queryTimeout.stop();
        availability = "na";
        try {
            const reply = JSON.parse(queryOutput.text);
            if (code === 0 && reply.type === "s" && reply.data.length === 1
                && ["yes", "challenge", "no", "na"].includes(reply.data[0]))
                availability = reply.data[0];
            else throw new Error("Invalid CanHibernate reply");
        } catch (failure) {
            fail(I18n.t("Failed to query hibernation support: %1", (queryError.text.trim() || String(failure))));
            return;
        }
        phase = "idle";
        if (!requested) {
            if (forceRequested) request(true);
            return;
        }
        if (!supported || !armed || !powerReady) {
            fail(reason);
            return;
        }
        if (!sessionLock) {
            fail(I18n.t("Lock screen not ready; operation cancelled."));
            return;
        }
        phase = "locking";
        lockTimeout.start();
        sessionLock.locked = true;
        submit();
    }

    function submit(): void {
        if (phase !== "locking" || !sessionLock?.secure) return;
        if (!armed || !powerReady) {
            fail(I18n.t("Pilot conditions changed; operation cancelled."));
            return;
        }
        lockTimeout.stop();
        phase = "submitting";
        startTimeout.start();
        power.running = true;
    }

    function resumed(): void {
        requested = false;
        phase = "idle";
        lockTimeout.stop();
        startTimeout.stop();
        forcing = false;
        forceRequested = false;
        closeDialog();
    }

    onPowerReadyChanged: {
        if (!powerReady && requested && phase !== "submitting")
            fail(I18n.t("Battery conditions changed; operation cancelled."));
    }

    onBatteryPercentageChanged: checkBatteryPolicy()
    onMeasuredBatteryPercentageChanged: checkBatteryPolicy()
    onBatteryAvailableChanged: checkBatteryPolicy()
    onOnBatteryChanged: checkBatteryPolicy()
    onPolicyEnabledChanged: {
        if (!policyEnabled) {
            prompted = false;
            forcing = false;
            forceRequested = false;
        } else checkBatteryPolicy();
    }

    Component.onCompleted: {
        refresh();
        checkBatteryPolicy();
    }

    Connections {
        target: root.sessionLock
        function onSecureStateChanged(): void { root.submit(); }
    }

    Connections {
        target: SessionManager
        function onResumed(): void { root.resumed(); }
    }

    Timer {
        id: queryTimeout
        interval: 5000
        onTriggered: {
            root.fail(I18n.t("Support query timed out."));
            query.running = false;
        }
    }
    Timer {
        id: lockTimeout
        interval: 5000
        onTriggered: root.fail(I18n.t("Lock confirmation failed; operation cancelled."))
    }
    Timer {
        id: startTimeout
        interval: 5000
        onTriggered: root.fail(I18n.t("Failed to initiate hibernation command."))
    }
    Timer {
        id: reserveTimer

        interval: 1000
        repeat: true
        onTriggered: {
            if (!root.dialogVisible || root.dialogStage !== "reserve") {
                stop();
                return;
            }
            if (root.dialogCountdown > 1) {
                root.dialogCountdown--;
                return;
            }
            root.dialogHibernate();
        }
    }
    Process {
        id: query
        command: root.checkCommand
        stdout: StdioCollector { id: queryOutput }
        stderr: StdioCollector { id: queryError }
        onExited: code => root.checked(code)
    }
    Process {
        id: power
        command: root.powerCommand
        stderr: StdioCollector { id: powerError }
        onStarted: startTimeout.stop()
        onExited: (code, status) => {
            if (code !== 0 || status !== 0)
                root.fail(I18n.t("Hibernation failed: %1", (powerError.text.trim() || String(code))));
            else root.resumed();
        }
    }
}
