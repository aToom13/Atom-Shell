pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services

Scope {
    id: root
    readonly property var prefs: GameProfiles.profile?.render ?? ({})
    readonly property var focused: Hyprland.activeToplevel
    readonly property var target: {
        if (!focused || !GameProfiles.profile)
            return null;
        const live = GameProfiles.windows.find(w => w.key === GameProfiles.selected);
        return focused.address === live?.address?.replace(/^0x/, "")
            || focused.lastIpcObject.class === GameProfiles.profile.appClass ? focused : null;
    }
    readonly property var output: Quickshell.screens.find(s => s.name === target?.monitor?.name) ?? null
    readonly property bool gameFocused: !!target && !!output && !GameProfiles.captureSuspended
    readonly property bool active: gameFocused && (prefs.hudEnabled ?? true)
        && ((prefs.hudFps ?? true) || prefs.hudCpu || prefs.hudRam || prefs.hudTemperature)
    property var sample: null
    property string error
    onTargetChanged: { sample = null; error = ""; }

    ServiceRef { service: root.active && (root.prefs.hudCpu || root.prefs.hudTemperature) ? Cpu : null }
    ServiceRef { service: root.active && root.prefs.hudRam ? Memory : null }

    Process {
        id: counter
        command: ["/bin/sh", Qt.resolvedUrl("../utils/game_fps.sh").toString().replace("file://", ""), String(root.target?.lastIpcObject.pid ?? 0)]
        // ponytail: XPresent covers XWayland games; native Wayland needs an application FPS source.
        running: root.gameFocused && !!root.target?.lastIpcObject.xwayland
            && Number(root.target?.lastIpcObject.pid ?? 0) > 0
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.sample = JSON.parse(line);
                    root.error = "";
                    if (root.sample.fps != null)
                        GameProfiles.reportGameFps(root.sample.fps);
                }
                catch (error) { root.error = String(error); }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim().slice(-300) }
        onExited: exitCode => {
            root.sample = null;
            if (exitCode !== 0 && exitCode !== 15 && root.active)
                root.error = I18n.t("Failed to start FPS measurement (%1)", exitCode);
        }
    }

    PanelWindow {
        id: hud
        readonly property bool right: (root.prefs.hudPosition ?? "top-right").endsWith("right")
        readonly property bool bottom: (root.prefs.hudPosition ?? "top-right").startsWith("bottom")
        readonly property int gap: root.prefs.hudMargin ?? 16
        screen: root.output
        visible: root.active
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "caelestia-game-hud"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors.left: true
        anchors.top: true
        margins.left: Math.max(0, (root.target?.lastIpcObject.at?.[0] ?? 0) - (root.target?.monitor?.x ?? 0)
            + (right ? (root.target?.lastIpcObject.size?.[0] ?? 0) - implicitWidth - gap : gap))
        margins.top: Math.max(0, (root.target?.lastIpcObject.at?.[1] ?? 0) - (root.target?.monitor?.y ?? 0)
            + (bottom ? (root.target?.lastIpcObject.size?.[1] ?? 0) - implicitHeight - gap : gap))
        implicitWidth: readings.implicitWidth + 24
        implicitHeight: readings.implicitHeight + 16

        Rectangle {
            anchors.fill: parent
            color: Colours.palette.m3surfaceContainer
            radius: Tokens.rounding.small
            border.color: Colours.palette.m3outlineVariant
            ColumnLayout {
                id: readings
                anchors.centerIn: parent
                spacing: 2
                Reading {
                    visible: root.prefs.hudFps ?? true
                    text: root.sample?.fps != null ? ("FPS " + Math.round(root.sample.fps)) : "FPS —"
                    color: Colours.palette.m3primary
                }
                Reading {
                    visible: (root.prefs.hudFps ?? true) && GameProfiles.captureRunning
                    text: !GameProfiles.captureInfo?.active ? I18n.t("Frame generation standby")
                        : GameProfiles.captureStats ? I18n.t("Delivered %1 FPS", Math.round(GameProfiles.captureStats.shown))
                        : I18n.t("Measuring frame generation…")
                }
                Reading { visible: !!root.prefs.hudCpu; text: qsTr("CPU  %1%").arg(Math.round(Cpu.percentage * 100)) }
                Reading { visible: !!root.prefs.hudRam; text: qsTr("RAM  %1% · %2 GB").arg(Math.round(Memory.percentage * 100)).arg((Memory.used / 1048576).toFixed(1)) }
                Reading { visible: !!root.prefs.hudTemperature; text: Cpu.temperature > 0 ? qsTr("CPU  %1 °C").arg(Math.round(Cpu.temperature)) : qsTr("CPU  — °C") }
            }
        }
    }
    component Reading: StyledText {
        font.pixelSize: root.prefs.hudFontSize ?? 16
        font.weight: Font.DemiBold
    }
    IpcHandler {
        target: "gameHud"
        function status(): string {
            return JSON.stringify({ active: root.active, title: root.target?.title, position: root.prefs.hudPosition ?? "top-right",
                fps: root.sample?.fps ?? null, source: root.sample?.source ?? "", counterRunning: counter.running,
                cpu: Cpu.percentage, ram: Memory.percentage, temperature: Cpu.temperature, error: root.error,
                nativeWaylandFpsSupported: false, inputPassthrough: true, x: hud.margins.left, y: hud.margins.top,
                focused: root.focused?.title, suspended: GameProfiles.captureSuspended, settings: root.prefs });
        }
    }
}
