import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
    id: root
    readonly property string address: String(Quickshell.env("CAELESTIA_CAPTURE_ADDRESS")).replace(/^0x/, "")
    readonly property var target: Hyprland.toplevels.values.find(t => t.address === address) ?? null
    readonly property var output: Quickshell.screens.find(s => s.name === target?.monitor?.name) ?? null
    readonly property bool active: !!target?.activated && !suspended && !!output
    property bool found: false
    property bool suspended: false
    property string error
    readonly property var targetData: target?.lastIpcObject ?? null
    readonly property string geometryKey: currentGeometry()
    property string lastGeometry: ""
    property bool moving: false

    function currentGeometry(): string {
        const data = target?.lastIpcObject;
        return data ? [data.at?.[0] ?? 0, data.at?.[1] ?? 0, data.size?.[0] ?? 0, data.size?.[1] ?? 0].join(":") : "";
    }
    function checkGeometry(): void {
        const key = currentGeometry();
        if (!key || key === lastGeometry)
            return;
        if (!lastGeometry) {
            lastGeometry = key;
            return;
        }
        lastGeometry = key;
        moving = true;
        moveTimer.restart();
    }

    function overlapsTarget(entry): bool {
        const data = entry?.lastIpcObject;
        if (!data || !targetData || entry.address === target?.address)
            return false;
        const x = targetData.at?.[0] ?? 0, y = targetData.at?.[1] ?? 0;
        const width = targetData.size?.[0] ?? 0, height = targetData.size?.[1] ?? 0;
        const otherX = data.at?.[0] ?? 0, otherY = data.at?.[1] ?? 0;
        const otherWidth = data.size?.[0] ?? 0, otherHeight = data.size?.[1] ?? 0;
        return width > 0 && height > 0 && otherWidth > 0 && otherHeight > 0
            && otherX < x + width && otherX + otherWidth > x
            && otherY < y + height && otherY + otherHeight > y;
    }
    readonly property bool appPopupVisible: {
        if (!target || !targetData)
            return false;
        return Hyprland.toplevels.values.some(entry => entry.lastIpcObject?.pid === targetData.pid && overlapsTarget(entry));
    }
    readonly property bool overlayVisible: active && !moving && !appPopupVisible

    onGeometryKeyChanged: checkGeometry()

    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            const name = event.name;
            const changesLayout = ["movewindow", "openwindow", "closewindow", "changefloatingmode", "fullscreen"]
                .some(prefix => name.startsWith(prefix));
            const interaction = changesLayout || ["activewindow", "windowtitle"].some(prefix => name.startsWith(prefix));
            if (changesLayout)
                Hyprland.refreshToplevels();
            if (interaction) {
                root.moving = true;
                moveTimer.restart();
            }
        }
    }

    function report(): void {
        console.warn("CAELESTIA_CAPTURE " + JSON.stringify({ active: root.active, ready: view.hasContent,
            title: root.target?.title ?? "", error: root.error }));
    }
    function fail(message: string): void {
        error = message;
        report();
        Qt.quit();
    }
    onTargetChanged: {
        if (target) {
            found = true;
        } else if (found) {
            report();
            Qt.quit();
        }
    }
    onActiveChanged: report()
    Component.onCompleted: report()

    PanelWindow {
        id: window
        screen: root.output
        visible: root.overlayVisible
        color: "transparent"
        // Input stays with the original application, including relative mouse input.
        mask: Region {}
        WlrLayershell.namespace: "caelestia-framegen"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors.top: true
        anchors.left: true
        margins.left: Math.max(0, (root.target?.lastIpcObject.at?.[0] ?? 0) - (root.target?.monitor?.x ?? 0))
        margins.top: Math.max(0, (root.target?.lastIpcObject.at?.[1] ?? 0) - (root.target?.monitor?.y ?? 0))
        implicitWidth: Math.max(1, root.target?.lastIpcObject.size?.[0] ?? 1)
        implicitHeight: Math.max(1, root.target?.lastIpcObject.size?.[1] ?? 1)

        ScreencopyView {
            id: view
            anchors.fill: parent
            captureSource: root.target?.wayland ?? null
            paintCursor: false
            live: root.active
            onHasContentChanged: root.report()
            onStopped: if (root.active) root.fail(qsTr("Pencere yakalama durdu."))
        }
    }

    Timer {
        interval: 66
        repeat: true
        running: root.active
        onTriggered: root.checkGeometry()
    }
    Timer {
        id: moveTimer
        interval: 350
        onTriggered: root.moving = false
    }
    Timer {
        interval: 8000
        running: !root.found || (root.active && !view.hasContent)
        onTriggered: root.fail(qsTr("Bu pencere yakalanamadı. Uygulamanın açık ve görünür olduğundan emin ol."))
    }
    IpcHandler {
        target: "frameCapture"
        function suspend(value: bool): void { root.suspended = value; }
        function stop(): void { Qt.quit(); }
        function status(): string {
            return JSON.stringify({ active: root.active, ready: view.hasContent, title: root.target?.title,
                address: root.address, output: root.output?.name, sourceSize: view.sourceSize,
                inputPassthrough: true, overlayVisible: root.overlayVisible, moving: root.moving,
                popupGuard: root.appPopupVisible, keyboardFocus: window.WlrLayershell.keyboardFocus, error: root.error });
        }
    }
}
