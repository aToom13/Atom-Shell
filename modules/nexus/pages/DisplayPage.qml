pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common
import "DisplayLayout.js" as DisplayLayout

PageBase {
    id: root

    title: qsTr("Ekranlar")
    property var monitors: []
    property var draft: []
    property string selectedName: ""
    property string error: ""
    property string connectionNotice: ""
    property string wirelessBackend: ""
    property var transaction: ({ phase: "idle" })
    property double clock: Date.now() / 1000
    readonly property bool pending: transaction.phase === "pending"
    readonly property bool busy: pending || transaction.phase === "applying" || action.running
    readonly property bool dirty: JSON.stringify(DisplayLayout.payload(monitors)) !== JSON.stringify(DisplayLayout.payload(draft))
    readonly property var selected: draft.find(m => m.name === selectedName) || null
    readonly property var mapBounds: DisplayLayout.bounds(draft)
    readonly property int secondsLeft: Math.max(0, Math.ceil((transaction.deadline || 0) - clock))
    readonly property list<string> helper: ["python3", Paths.toLocalFile(Qt.resolvedUrl("../../../utils/display_settings.py"))]
    readonly property var resolutions: selected ? [...new Set(selected.availableModes.map(v => v.split("@")[0]))] : []
    readonly property string resolution: selected ? selected.mode.split("@")[0] : ""
    readonly property var rates: selected ? selected.availableModes.filter(v => v.startsWith(resolution + "@")).map(v => v.split("@")[1]) : []
    readonly property var scaleValues: selected ? [...new Set([0.75, 1, 1.25, 1.5, 1.75, 2, selected.scale])].filter(v => {
        const p = DisplayLayout.modeParts(selected.mode);
        return v === selected.scale || (Math.abs(p.width/v-Math.round(p.width/v)) < 0.01 && Math.abs(p.height/v-Math.round(p.height/v)) < 0.01);
    }).sort((a,b) => a-b) : []

    function edit(values): void {
        if (!selected || busy) return;
        draft = draft.map(m => m.name === selectedName ? Object.assign({}, m, values) : m);
    }

    function nudge(name: string, dx: int, dy: int): void {
        selectedName = name;
        edit({x:selected.x+dx, y:selected.y+dy});
        Qt.callLater(() => {
            for (let i=0; i<tiles.count; i++) {
                const item = tiles.itemAt(i);
                if (item && item.modelData.name === name) item.forceActiveFocus();
            }
        });
    }

    function refresh(): void {
        if (!monitorProc.running) monitorProc.running = true;
        poll();
    }

    function poll(): void {
        if (!stateProc.running) stateProc.running = true;
    }

    function act(command: string): void {
        if (action.running) return;
        error = "";
        action.command = [...helper, command, command === "preview" ? JSON.stringify(DisplayLayout.payload(draft)) : transaction.token];
        action.running = true;
    }

    function acceptState(value: var): void {
        const wasBusy = pending || transaction.phase === "applying";
        transaction = value;
        if (wasBusy && !pending && value.phase !== "applying") {
            draft = [];
            refresh();
        }
    }

    function arrange(kind: string): void {
        if (!busy) draft = DisplayLayout.preset(draft, kind);
    }

    function coordinates(axis: string): var {
        if (!selected) return [0];
        const size = DisplayLayout.geometry(selected);
        const values = [selected[axis], 0];
        for (const peer of draft.filter(m => m.name !== selectedName && m.enabled && !m.mirror)) {
            const length = axis === "x" ? "width" : "height";
            const other = DisplayLayout.geometry(peer);
            values.push(peer[axis], peer[axis]+other[length], peer[axis]-size[length]);
        }
        return [...new Set(values.map(Math.round))].sort((a,b) => a-b);
    }

    function align(direction: string): void {
        if (!selected) return;
        const peer = draft.find(m => m.name !== selectedName && m.enabled && !m.mirror);
        if (!peer) return;
        const size = DisplayLayout.geometry(selected), other = DisplayLayout.geometry(peer);
        edit({ x: Math.round(direction === "left" ? peer.x-size.width : direction === "right" ? peer.x+other.width : peer.x),
            y: Math.round(direction === "above" ? peer.y-size.height : direction === "below" ? peer.y+other.height : peer.y), mirror: "" });
    }

    Component.onCompleted: { refresh(); wirelessProbe.running = true; }

    property Connections hyprEvents: Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "focusedmon", "configreloaded"].includes(event.name)) refreshDelay.restart();
        }
    }

    property Timer refreshTimer: Timer { id: refreshDelay; interval: 300; onTriggered: root.refresh() }
    property Timer pollTimer: Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: { root.clock = Date.now()/1000; root.poll(); }
    }

    property Process monitorProcess: Process {
        id: monitorProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const next = JSON.parse(text).map(DisplayLayout.fromMonitor);
                    const topology = next.map(m => m.name).sort().join(",");
                    const oldTopology = root.monitors.map(m => m.name).sort().join(",");
                    const keepDraft = root.dirty && root.draft.length && topology === oldTopology && !root.busy;
                    if (oldTopology && topology !== oldTopology) root.connectionNotice = qsTr("Ekran bağlantısı değişti; liste güncellendi.");
                    root.monitors = next;
                    if (!keepDraft) root.draft = next.map(m => Object.assign({}, m));
                    if (!root.draft.some(m => m.name === root.selectedName)) root.selectedName = next.find(m => m.focused)?.name || next[0]?.name || "";
                } catch (e) { root.error = qsTr("Ekran bilgileri okunamadı: ") + e; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim() }
    }

    property Process stateProcess: Process {
        id: stateProc
        command: [...root.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.acceptState(JSON.parse(text)); }
                catch (e) { root.error = qsTr("Ekran denemesinin durumu okunamadı."); }
            }
        }
    }

    property Process actionProcess: Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    if (value.phase === "error") root.error = value.message;
                    else root.acceptState(value);
                } catch (e) { root.error = qsTr("Ekran işlemi tamamlanamadı."); }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim() }
        onExited: root.refreshDelay.restart()
    }

    property Process wirelessProcess: Process {
        id: wirelessProbe
        command: ["sh", "-c", "if command -v gnome-network-displays >/dev/null 2>&1; then echo native; elif flatpak info org.gnome.NetworkDisplays >/dev/null 2>&1; then echo flatpak; else echo none; fi"]
        stdout: StdioCollector { onStreamFinished: root.wirelessBackend = text.trim() }
    }

    component Choice: Controls.ComboBox {
        id: control
        implicitHeight: 44
        font: Tokens.font.body.medium
        palette.text: Colours.palette.m3onSurface
        palette.buttonText: Colours.palette.m3onSurface
        palette.base: Colours.palette.m3surfaceContainerHigh
        palette.button: Colours.palette.m3surfaceContainerHigh
        palette.window: Colours.palette.m3surfaceContainerHigh
        palette.windowText: Colours.palette.m3onSurface
        palette.highlight: Colours.palette.m3primary
        palette.highlightedText: Colours.palette.m3onPrimary
        background: StyledRect {
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerHigh
            border.width: control.activeFocus ? 2 : 1
            border.color: control.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outline, 0.25)
            opacity: control.enabled ? 1 : 0.45
        }
        contentItem: Controls.TextField {
            text: control.editable ? control.editText : control.displayText
            font: control.font
            color: control.enabled ? Colours.palette.m3onSurface : Colours.palette.m3outline
            selectionColor: Colours.palette.m3primary
            selectedTextColor: Colours.palette.m3onPrimary
            verticalAlignment: TextInput.AlignVCenter
            leftPadding: 12; rightPadding: 36
            readOnly: !control.editable
            enabled: control.editable
            selectByMouse: control.editable
            validator: control.validator
            background: null
        }
        indicator: MaterialIcon {
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: control.popup.visible ? "expand_less" : "expand_more"
            color: Colours.palette.m3onSurfaceVariant
        }
        delegate: Controls.ItemDelegate {
            required property var modelData
            required property int index
            width: control.width-8
            height: 40
            highlighted: control.highlightedIndex === index
            contentItem: StyledText {
                text: modelData; font: control.font
                color: parent.highlighted ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: StyledRect {
                radius: Tokens.rounding.small
                color: parent.highlighted ? Colours.palette.m3primaryContainer : "transparent"
            }
        }
        popup: Controls.Popup {
            y: control.height+4
            width: control.width
            padding: 4
            implicitHeight: Math.min(248, list.contentHeight+8)
            background: StyledRect {
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh
                border.width: 1; border.color: Qt.alpha(Colours.palette.m3outline, 0.3)
            }
            contentItem: ListView {
                id: list
                clip: true
                model: control.popup.visible ? control.delegateModel : null
                currentIndex: control.highlightedIndex
                Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {}
            }
        }
    }

    component Label: StyledText {
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        ConnectedRect {
            Layout.fillWidth: true
            first: true; last: true
            color: root.pending ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainer
            implicitHeight: actions.implicitHeight + 32
            ColumnLayout {
                id: actions
                anchors.fill: parent; anchors.margins: 16
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    MaterialIcon { text: root.pending ? "timer" : "desktop_windows"; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.large }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: root.pending ? qsTr("Bu düzen kalsın mı? · %1 sn").arg(root.secondsLeft) : qsTr("Çalışma alanını düzenle")
                            font: Tokens.font.title.medium; wrapMode: Text.WordWrap
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.pending ? qsTr("Onaylamazsan önceki ayarlara otomatik dönülür.") : root.transaction.phase === "applying" ? qsTr("Ayarlar deneniyor…") : qsTr("%1 ekran bağlı · Değişiklikler Uygula ile denenir").arg(root.monitors.length)
                            color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.body.small; wrapMode: Text.WordWrap
                        }
                    }
                    IconButton { icon: "refresh"; type: IconButton.Text; disabled: monitorProc.running || root.busy; onClicked: root.refresh(); Accessible.name: qsTr("Ekranları yenile") }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    TextButton {
                        text: root.pending ? qsTr("Geri al") : qsTr("Değişiklikleri sıfırla")
                        type: TextButton.Tonal
                        disabled: action.running || (!root.pending && (!root.dirty || root.busy))
                        onClicked: { if (root.pending) root.act("revert"); else root.draft = root.monitors.map(m => Object.assign({}, m)); }
                    }
                    Item { Layout.fillWidth: true }
                    TextButton {
                        text: root.pending ? qsTr("Bu ayarlar kalsın") : qsTr("Uygula")
                        type: TextButton.Filled
                        disabled: action.running || (root.pending ? root.secondsLeft === 0 : !root.dirty || root.busy || !root.draft.length)
                        onClicked: root.act(root.pending ? "confirm" : "preview")
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !!root.error || root.transaction.phase === "error" || root.transaction.phase === "saved" || root.transaction.phase === "reverted" || !!root.connectionNotice
            text: root.error || (["error", "saved", "reverted"].includes(root.transaction.phase) ? root.transaction.message : root.connectionNotice)
            color: root.error || root.transaction.phase === "error" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap; font: Tokens.font.body.small
        }

        SectionHeader { text: qsTr("Yerleşim") }

        StyledRect {
            id: map
            objectName: "displayMap"
            Layout.fillWidth: true
            implicitHeight: 230
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerLow
            clip: true
            readonly property real factor: Math.min((width-56)/Math.max(1,root.mapBounds.width), (height-56)/Math.max(1,root.mapBounds.height))
            readonly property real offsetX: (width-root.mapBounds.width*factor)/2
            readonly property real offsetY: (height-root.mapBounds.height*factor)/2
            Repeater {
                id: tiles
                model: root.draft.filter(m => m.enabled && !m.mirror)
                delegate: StyledRect {
                    id: tile
                    required property var modelData
                    readonly property var size: DisplayLayout.geometry(modelData)
                    readonly property bool chosen: root.selectedName === modelData.name
                    x: map.offsetX + (modelData.x-root.mapBounds.x)*map.factor
                    y: map.offsetY + (modelData.y-root.mapBounds.y)*map.factor
                    width: Math.max(48, size.width*map.factor)
                    height: Math.max(40, size.height*map.factor)
                    z: dragArea.drag.active ? 3 : chosen ? 2 : 1
                    radius: Tokens.rounding.small
                    color: chosen ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest
                    border.width: chosen ? 2 : 1
                    border.color: chosen ? Colours.palette.m3primary : Colours.palette.m3outline
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("%1 ekranı, konum %2, %3. Ok tuşlarıyla taşı.").arg(modelData.name).arg(modelData.x).arg(modelData.y)
                    Keys.onLeftPressed: root.nudge(modelData.name,-10,0)
                    Keys.onRightPressed: root.nudge(modelData.name,10,0)
                    Keys.onUpPressed: root.nudge(modelData.name,0,-10)
                    Keys.onDownPressed: root.nudge(modelData.name,0,10)
                    Column {
                        anchors.centerIn: parent; width: parent.width-12; spacing: 4
                        StyledText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: tile.modelData.name; font: Tokens.font.title.small; elide: Text.ElideRight }
                        StyledText { width: parent.width; visible: tile.height > 72; horizontalAlignment: Text.AlignHCenter; text: tile.modelData.mode.split("@")[0]; color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.label.small; elide: Text.ElideRight }
                    }
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        enabled: !root.busy
                        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        drag.target: tile
                        onPressed: { root.selectedName = tile.modelData.name; tile.forceActiveFocus(); }
                        onReleased: {
                            const next = DisplayLayout.snap(root.draft, tile.modelData.name,
                                (tile.x-map.offsetX)/map.factor+root.mapBounds.x,
                                (tile.y-map.offsetY)/map.factor+root.mapBounds.y);
                            root.edit(next);
                            tile.x = Qt.binding(() => map.offsetX+(tile.modelData.x-root.mapBounds.x)*map.factor);
                            tile.y = Qt.binding(() => map.offsetY+(tile.modelData.y-root.mapBounds.y)*map.factor);
                        }
                    }
                }
            }
            StyledText {
                anchors.centerIn: parent
                visible: !root.draft.some(m => m.enabled && !m.mirror)
                text: qsTr("En az bir ekranı etkinleştir.")
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        Label { Layout.fillWidth: true; text: qsTr("Ekranları sürükle; kenarlar birbirine hizalanır. Klavyeyle: Tab ve ok tuşları."); wrapMode: Text.WordWrap }

        Flow {
            Layout.fillWidth: true; spacing: 8
            Repeater {
                model: root.draft
                delegate: TextButton {
                    required property var modelData
                    text: modelData.name + (modelData.enabled ? modelData.mirror ? qsTr(" · Yansıtma") : "" : qsTr(" · Kapalı"))
                    type: root.selectedName === modelData.name ? TextButton.Filled : TextButton.Tonal
                    onClicked: root.selectedName = modelData.name
                }
            }
        }

        Flow {
            Layout.fillWidth: true; spacing: 8
            visible: root.draft.length > 1
            enabled: !root.busy
            TextButton { text: qsTr("Genişlet"); type: TextButton.Tonal; onClicked: root.arrange("extend") }
            TextButton { text: qsTr("Aynala"); type: TextButton.Tonal; onClicked: root.arrange("mirror") }
            TextButton { text: qsTr("Yalnızca dizüstü"); type: TextButton.Tonal; disabled: !root.draft.some(m => /^(eDP|LVDS|DSI)/i.test(m.name)); onClicked: root.arrange("internal") }
            TextButton { text: qsTr("Yalnızca harici"); type: TextButton.Tonal; disabled: !root.draft.some(m => !/^(eDP|LVDS|DSI)/i.test(m.name)); onClicked: root.arrange("external") }
        }

        ConnectedRect {
            Layout.fillWidth: true
            visible: !!root.selected
            first: true; last: true
            implicitHeight: details.implicitHeight + 32
            ColumnLayout {
                id: details
                anchors.fill: parent; anchors.margins: 16
                spacing: 14
                RowLayout {
                    Layout.fillWidth: true
                    MaterialIcon { text: root.selected?.enabled ? "monitor" : "desktop_access_disabled"; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.large }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        StyledText { text: root.selected?.name || ""; font: Tokens.font.title.medium }
                        Label { Layout.fillWidth: true; text: root.selected?.description || ""; elide: Text.ElideRight }
                        Label { text: root.monitors.find(m => m.name === root.selectedName)?.focused ? qsTr("Odaklanan ekran") : root.selected?.enabled ? qsTr("Etkin ekran") : qsTr("Kapalı ekran") }
                    }
                    StyledSwitch {
                        checked: root.selected?.enabled || false
                        disabled: root.busy || (checked && root.draft.filter(m => m.enabled && !m.mirror).length === 1 && !root.selected?.mirror)
                        Accessible.name: qsTr("Seçilen ekranı etkinleştir")
                        onToggled: root.edit({enabled:checked, mirror:""})
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: width < 380 ? 1 : 2
                    columnSpacing: 12; rowSpacing: 12
                    enabled: !!root.selected?.enabled && !root.busy
                    ColumnLayout {
                        Layout.fillWidth: true
                        Label { text: qsTr("Çözünürlük") }
                        Choice {
                            objectName: "resolutionChoice"
                            Layout.fillWidth: true; model: root.resolutions
                            currentIndex: root.resolutions.indexOf(root.resolution)
                            Accessible.name: qsTr("Çözünürlük")
                            onActivated: {
                                const mode = root.selected.availableModes.find(v => v.startsWith(currentText+"@") && Math.abs(DisplayLayout.modeParts(v).hz-DisplayLayout.modeParts(root.selected.mode).hz)<0.06) || root.selected.availableModes.find(v => v.startsWith(currentText+"@"));
                                if (mode) root.edit({mode});
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Label { text: qsTr("Yenileme hızı") }
                        Choice {
                            objectName: "rateChoice"
                            Layout.fillWidth: true; model: root.rates.map(v => v+" Hz")
                            currentIndex: root.selected ? root.rates.indexOf(root.selected.mode.split("@")[1]) : -1
                            Accessible.name: qsTr("Yenileme hızı")
                            onActivated: root.edit({mode:root.resolution+"@"+root.rates[currentIndex]})
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Label { text: qsTr("Ölçek") }
                        Choice {
                            objectName: "scaleChoice"
                            Layout.fillWidth: true; model: root.scaleValues.map(v => Math.round(v*100)+"%")
                            currentIndex: root.selected ? root.scaleValues.indexOf(root.selected.scale) : -1
                            Accessible.name: qsTr("Ekran ölçeği")
                            onActivated: root.edit({scale:root.scaleValues[currentIndex]})
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Label { text: qsTr("Döndürme") }
                        Choice {
                            objectName: "rotationChoice"
                            Layout.fillWidth: true
                            model: [qsTr("Normal"), qsTr("90°"), qsTr("180°"), qsTr("270°"), qsTr("Yatay çevir"), qsTr("Çevir + 90°"), qsTr("Çevir + 180°"), qsTr("Çevir + 270°")]
                            currentIndex: root.selected?.transform || 0
                            Accessible.name: qsTr("Ekranı döndür")
                            onActivated: root.edit({transform:currentIndex})
                        }
                    }
                }

                Label { visible: !!root.selected?.mirror; text: qsTr("%1 ekranını yansıtıyor.").arg(root.selected?.mirror || "") }

                RowLayout {
                    Layout.fillWidth: true
                    enabled: !!root.selected?.enabled && !root.selected?.mirror && !root.busy
                    Label { text: "X" }
                    Choice {
                        objectName: "xPositionChoice"
                        Layout.fillWidth: true; editable: true
                        model: root.coordinates("x").map(String)
                        currentIndex: root.coordinates("x").indexOf(root.selected?.x || 0)
                        validator: IntValidator { bottom: -32768; top: 32768 }
                        Accessible.name: qsTr("Yatay konum")
                        onActivated: root.edit({x:Number(currentText)})
                        onAccepted: { if (acceptableInput && editText.trim()) root.edit({x:Number(editText)}); }
                    }
                    Label { text: "Y" }
                    Choice {
                        objectName: "yPositionChoice"
                        Layout.fillWidth: true; editable: true
                        model: root.coordinates("y").map(String)
                        currentIndex: root.coordinates("y").indexOf(root.selected?.y || 0)
                        validator: IntValidator { bottom: -32768; top: 32768 }
                        Accessible.name: qsTr("Dikey konum")
                        onActivated: root.edit({y:Number(currentText)})
                        onAccepted: { if (acceptableInput && editText.trim()) root.edit({y:Number(editText)}); }
                    }
                }
                Flow {
                    Layout.fillWidth: true; spacing: 6
                    visible: root.draft.filter(m => m.enabled && !m.mirror && m.name !== root.selectedName).length > 0
                    enabled: !!root.selected?.enabled && !root.busy
                    TextButton { text: qsTr("Sola hizala"); type: TextButton.Tonal; onClicked: root.align("left") }
                    TextButton { text: qsTr("Sağa hizala"); type: TextButton.Tonal; onClicked: root.align("right") }
                    TextButton { text: qsTr("Üste hizala"); type: TextButton.Tonal; onClicked: root.align("above") }
                    TextButton { text: qsTr("Alta hizala"); type: TextButton.Tonal; onClicked: root.align("below") }
                }
            }
        }

        SectionHeader { text: qsTr("Kablosuz ekran") }
        ConnectedRect {
            Layout.fillWidth: true
            first: true; last: true
            implicitHeight: wireless.implicitHeight + 32
            ColumnLayout {
                id: wireless
                anchors.fill: parent; anchors.margins: 16
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    MaterialIcon { text: "cast"; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.large }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        StyledText { text: "GNOME Network Displays"; font: Tokens.font.title.small }
                        Label { text: root.wirelessBackend === "" ? qsTr("Kontrol ediliyor…") : root.wirelessBackend === "none" ? qsTr("Bu bilgisayarda kurulu değil") : qsTr("Kurulu · Miracast") }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("TV'de ekran yansıtmayı aç. Ekran bulma, bağlanma ve bağlantıyı kesme uygulamanın içinde yapılır.")
                    color: Colours.palette.m3onSurfaceVariant; wrapMode: Text.WordWrap; font: Tokens.font.body.small
                }
                IconTextButton {
                    text: qsTr("Kablosuz ekrana bağlan"); icon: "open_in_new"; type: IconTextButton.Tonal
                    disabled: !root.wirelessBackend || root.wirelessBackend === "none"
                    onClicked: {
                        root.error = "";
                        Quickshell.execDetached(root.wirelessBackend === "flatpak" ? ["flatpak","run","org.gnome.NetworkDisplays"] : ["gnome-network-displays"]);
                    }
                }
            }
        }
    }
}
