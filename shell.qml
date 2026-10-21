//@ pragma Env QS_CRASHREPORT_URL=https://github.com/aToom13/Atom-Shell/issues
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
//@ pragma DefaultEnv QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import "modules"
import "modules/drawers"
import "modules/background"
import "modules/areapicker"
import "modules/lock"
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services

ShellRoot {
    id: root

    property alias hibernation: hibernation

    HibernationController {
        id: hibernation
        sessionLock: lock.lock
        onFailed: message => Toaster.toast(I18n.t("Hibernate"), message, "bedtime", Toast.Error)
        onDialogActionPreviewed: stage => Toaster.toast(I18n.t("UI preview"), stage === "reserve" ? I18n.t("Shutdown button previewed") : I18n.t("Hibernate button previewed"), "bedtime")
    }

    IpcHandler {
        target: "hibernation"
        function arm(): void { hibernation.arm(); }
        function disarm(): void { hibernation.disarm(); }
        function previewPrompt(): void { hibernation.previewDialog("prompt"); }
        function previewReserve(): void { hibernation.previewDialog("reserve"); }
        function closeDialog(): void { hibernation.closeDialog(); }
        function dismiss(): void { hibernation.dialogDismiss(); }
        function status(): string { return JSON.stringify({armed: hibernation.armed, policyEnabled: hibernation.policyEnabled, onBattery: hibernation.onBattery, measuredPercentage: hibernation.measuredBatteryPercentage, displayedPercentage: hibernation.batteryPercentage, batteryAvailable: hibernation.batteryAvailable, busy: hibernation.busy, availability: hibernation.availability, reason: hibernation.reason}); }
        function dialogStatus(): string { return JSON.stringify({visible: hibernation.dialogVisible, stage: hibernation.dialogStage, countdown: hibernation.dialogCountdown, previewOnly: hibernation.dialogPreviewOnly}); }
    }

    Loader {
        active: Quickshell.env("CAELESTIA_CHECK_DRAWERS") === "1"
        source: "utils/CheckDrawers.qml"
    }

    settings.watchFiles: false

    Binding {
        target: ShellState
        property: "shellRoot"
        value: root
    }

    GSFLoader {}
    ServiceLoader {}

    Background {}
    Drawers {}
    HibernationDialogs {
        hibernation: root.hibernation
    }
    AreaPicker {}
    Lock {
        id: lock
    }

    ConfigToasts {}
    Shortcuts {}
    BatteryMonitor {}
    GameHud {}
    Dictation { locked: lock.lock.locked }
    IdleMonitors {
        lock: lock
    }
}
