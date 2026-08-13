pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Shares a smooth power estimate across every Battery UI.
//
// The stock UPower timeToEmpty extrapolates the instantaneous current draw,
// so the "time remaining" number jumps wildly as the CPU breathes.
// This singleton keeps a short power history instead:
//   - avgPower1Min   -> arithmetic mean of the last 1 minute (refreshed every 5s)
//   - avgPower       -> EMA with a 15 minute time constant
//   - estimateSeconds -> remaining energy / EMA power, in the same units as
//                        UPower.displayDevice.timeToEmpty / timeToFull
//
// The singleton lives for the whole shell process, so history survives
// popup open/close cycles and Quickshell hot reloads (see reload()).

Singleton {
    id: root

    // History of [unixMs, watts] samples, oldest first.
    readonly property var history: _history
    property var _history: []

    // Exponential moving average of power draw (watts).
    readonly property real avgPower: _avgPower
    property real _avgPower: 0

    // Mean of the samples recorded in the last 60 seconds (watts).
    readonly property real avgPower1Min: _avgPower1Min
    property real _avgPower1Min: 0

    // A useful estimate needs a warm-up window: until the history has enough
    // samples the smoothed numbers are nonsense (a 0 W sample extrapolates to
    // absurd multi-day estimates). On cold boot the shell therefore falls back
    // to UPower's raw instantaneous values instead of flashing nonsense.
    readonly property int minSamples: 12
    readonly property real minPowerWatts: 1.0

    readonly property bool hasData: _history.length >= minSamples && _avgPower > minPowerWatts

    // Smoothed seconds until empty; mirrors UPower's timeToEmpty.
    // Before warm-up completes, falls back to the raw UPower value.
    readonly property int estimatedSeconds: UPower.onBattery ? (hasData ? _estimateSeconds : Math.max(UPower.displayDevice.timeToEmpty, 0)) : 0
    property int _estimateSeconds: 0

    function _sample(): void {
        const now = Date.now();
        const watts = Math.abs(UPower.displayDevice.changeRate);
        if (!Number.isFinite(watts))
            return;

        const cutoff = now - 15 * 60 * 1000;
        const pruned = _history.filter(s => s[0] >= cutoff);
        pruned.push([now, watts]);
        root._history = pruned;

        // EMA with time constant tau = 15 min: alpha = 1 - exp(-dt/tau).
        if (pruned.length === 1) {
            root._avgPower = watts;
        } else {
            const prev = pruned[pruned.length - 2][0];
            const dt = (now - prev) / 1000;
            const alpha = 1 - Math.exp(-dt / 900);
            root._avgPower = _avgPower + alpha * (watts - _avgPower);
        }

        const oneMinCutoff = now - 60 * 1000;
        const oneMin = pruned.filter(s => s[0] >= oneMinCutoff);
        root._avgPower1Min = oneMin.length ? oneMin.reduce((acc, s) => acc + s[1], 0) / oneMin.length : 0;

        if (UPower.onBattery && _avgPower > minPowerWatts) {
            const wh = UPower.displayDevice.energy;
            root._estimateSeconds = Math.round(wh / _avgPower * 3600);
        }
    }

    function _reset(): void {
        root._history = [];
        root._avgPower = 0;
        root._avgPower1Min = 0;
        root._estimateSeconds = 0;
    }

    // State transfer on Quickshell hot reload.
    function reload(old: var): void {
        if (old) {
            root._history = old._history;
            root._avgPower = old._avgPower;
            root._avgPower1Min = old._avgPower1Min;
            root._estimateSeconds = old._estimateSeconds;
        }
    }

    Timer {
        id: sampler

        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: UPower.displayDevice.isPresent
        onTriggered: root._sample()
    }

    Connections {
        target: UPower

        // Reset on plug/unplug so charge and discharge curves never mix.
        function onOnBatteryChanged(): void {
            root._reset();
        }
    }
}