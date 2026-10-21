pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import Caelestia
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root
    required property LazyLoader loader
    required property ShellScreen screen
    property var selectedClient: null
    property bool application: false
    property bool selected: false
    property bool capturing: false
    property string error: ""
    property bool appListOpen: false
    property bool liveAdjust: false
    property bool liveReady: false
    property bool endingLive: false
    property var captureSource: null
    property string filter: ""
    readonly property var filteredApps: applications.filter(c => ((c.title ?? "") + " " + c.lastIpcObject.class).toLocaleLowerCase().includes(filter.toLocaleLowerCase()))
    property real sx: 0
    property real sy: 0
    property real ex: screen.width
    property real ey: screen.height
    readonly property real rx: Math.max(0, Math.min(sx, ex))
    readonly property real ry: Math.max(0, Math.min(sy, ey))
    readonly property real rw: Math.min(screen.width, Math.max(sx, ex)) - rx
    readonly property real rh: Math.min(screen.height, Math.max(sy, ey)) - ry
    readonly property bool current: loader.selectedOutput === screen.name
    readonly property var clients: Hypr.toplevels.values.filter(c => {
        const d = c.lastIpcObject;
        const mon = Hypr.monitorFor(screen);
        return d.mapped && !d.hidden && (d.pinned || c.workspace?.id === (mon?.lastIpcObject.specialWorkspace?.name ? mon.lastIpcObject.specialWorkspace.id : mon?.activeWorkspace.id));
    }).sort((a,b) => (b.lastIpcObject.floating - a.lastIpcObject.floating) || ((a.lastIpcObject.focusHistoryID ?? 999) - (b.lastIpcObject.focusHistoryID ?? 999)));
    readonly property var applications: Hypr.toplevels.values.filter(c => c.lastIpcObject.mapped && !c.lastIpcObject.hidden && c.wayland);

    function pick(client): void {
        selectedClient = client;
        if (!client) return;
        const d = client.lastIpcObject;
        sx = Math.max(0, d.at[0] - screen.x);
        sy = Math.max(0, d.at[1] - screen.y);
        ex = Math.min(screen.width, d.at[0] - screen.x + d.size[0]);
        ey = Math.min(screen.height, d.at[1] - screen.y + d.size[1]);
    }
    function hover(x,y): void {
        if (selected || capturing || application) return;
        pick(clients.find(c => {
            const d=c.lastIpcObject;
            return x >= d.at[0]-screen.x && y >= d.at[1]-screen.y && x < d.at[0]-screen.x+d.size[0] && y < d.at[1]-screen.y+d.size[1];
        }) ?? null);
    }
    function source(): var {
        return application && selectedClient ? {kind:"window",window:selectedClient.lastIpcObject}
            : {kind:"region",output:screen.name,x:Math.round(rx),y:Math.round(ry),width:Math.floor(rw),height:Math.floor(rh),
               window:selectedClient?.lastIpcObject ?? JSON.parse(loader.captureWindow)};
    }
    function adjust(dx, dy, resize): void {
        if (!current || capturing) return;
        const x=rx, y=ry, w=rw, h=rh;
        application=false; selected=true; selectedClient=null; appListOpen=false;
        sx=resize ? x : Math.max(0,Math.min(screen.width-w,x+dx));
        sy=resize ? y : Math.max(0,Math.min(screen.height-h,y+dy));
        ex=sx+(resize ? Math.max(2,Math.min(screen.width-sx,w+dx)) : w);
        ey=sy+(resize ? Math.max(2,Math.min(screen.height-sy,h+dy)) : h);
        if (loader.video && loader.recording.recording && !loader.recording.busy && !liveAdjust) {
            liveAdjust=true;
            loader.resumeOnClose=true;
            liveEditStart.restart();
        }
        forceActiveFocus();
    }
    function showControls(): void {
        liveReady=false;
        liveEditStart.stop();
        endingLive=true;
        if (loader.recording.paused) finishLiveEditing();
        else loader.recording.setPaused(true);
    }
    function finishLiveEditing(): void {
        screenCopy.captureSource=null;
        screenCopy.captureSource=screen;
        liveAdjust=false;
        endingLive=false;
    }
    function resume(): void {
        const target=source();
        loader.hideForCapture();
        loader.recording.applySelection(target);
    }
    function capture(): void {
        if (capturing || loader.saver.running || (!application && (rw < 2 || rh < 2)) || (application && !selectedClient)) return;
        if (loader.video) {
            const target = source();
            loader.hideForCapture();
            loader.recording.start(target, loader.sound);
        } else {
            captureSource = source();
            capturing = true;
            error = "";
            if (application) {
                windowCopy.captureSource = null;
                windowCopy.captureSource = selectedClient.wayland;
                windowCopy.live = false;
                if (windowCopy.hasContent) save(windowCopy, true);
            } else if (loader.freeze && screenCopy.hasContent) save(screenCopy, false);
            else { screenCopy.live = true; liveTimer.restart(); }
        }
    }
    function save(item, whole): void {
        const temporary = Qt.resolvedUrl(root.loader.ocr
            ? `${Quickshell.env("XDG_RUNTIME_DIR")}/desktop-assist/ocr-${Quickshell.processId}-${Date.now()}.png`
            : `/tmp/caelestia-picker-${Quickshell.processId}-${Date.now()}.png`);
        const rect = whole ? Qt.rect(0,0,item.width,item.height) : Qt.rect(Math.ceil(rx),Math.ceil(ry),Math.floor(rw),Math.floor(rh));
        CUtils.saveItem(item, temporary, rect, path => {
            loader.saver.ocr = loader.ocr;
            loader.saver.exec(loader.ocr
                ? ["python3", `${Quickshell.env("HOME")}/.config/hypr/scripts/desktop-assist.py`, "ocr-image", path]
                : ["/usr/bin/python3","-m","caelestia.utils.capture",path,JSON.stringify(captureSource.window)]);
            loader.dismiss();
        }, message => { capturing = false; error = I18n.t("Failed to save image: %1", message); });
    }
    function chooseApp(client): void {
        application=true; selected=true; pick(client); appListOpen=false; forceActiveFocus();
    }
    anchors.fill: parent
    focus: true
    onCurrentChanged: if (current) loader.activePicker=root
    Component.onDestruction: { if (loader.activePicker === root) loader.activePicker=null; }
    Keys.onPressed: event => {
        if (!(event.modifiers & Qt.MetaModifier) || !(event.modifiers & (Qt.AltModifier | Qt.ShiftModifier))) return;
        const directions={};
        directions[Qt.Key_Left]=[-10,0]; directions[Qt.Key_Right]=[10,0];
        directions[Qt.Key_Up]=[0,-10]; directions[Qt.Key_Down]=[0,10];
        const delta=directions[event.key];
        if (delta) { adjust(delta[0],delta[1],!!(event.modifiers & Qt.AltModifier)); event.accepted=true; }
    }
    Keys.onEscapePressed: { if (appListOpen) { appListOpen=false; forceActiveFocus(); } else loader.dismiss(); }
    Keys.onReturnPressed: { if (!appListOpen) capture(); }
    Keys.onEnterPressed: { if (!appListOpen) capture(); }
    Component.onCompleted: {
        if (current) loader.activePicker=root;
        const previous=loader.recording.source;
        if (previous && loader.recording.recording) {
            if (previous.kind === "window") {
                const c=applications.find(c=>c.lastIpcObject.address===previous.window.address);
                if (c) { application=true; selected=true; pick(c); }
            } else if (previous.output === screen.name) {
                sx=previous.x; sy=previous.y; ex=sx+previous.width; ey=sy+previous.height; selected=true;
            }
        } else pick(clients[0] ?? null);
    }
    Connections {
        target: root.loader.recording
        function onPausedChanged(): void {
            if (root.endingLive && root.loader.recording.paused) root.finishLiveEditing();
        }
    }
    Timer {
        id: liveEditStart
        interval:80
        onTriggered: { root.liveReady=true; root.loader.recording.applySelection(root.source()); }
    }
    Timer {
        interval:33; repeat:true; running:root.liveAdjust && root.liveReady
        onTriggered: {
            if (!root.loader.recording.busy && !root.loader.recording.sameSource(root.source()))
                root.loader.recording.applySelection(root.source());
        }
    }

    ScreencopyView {
        id: screenCopy
        anchors.fill: parent
        captureSource: root.screen
        live: false
        paintCursor: false
        visible: !root.liveAdjust && (!root.capturing || root.loader.freeze)
    }
    ScreencopyView {
        id: windowCopy
        x: -width - 10
        width: Math.max(2, selectedClient?.lastIpcObject.size[0] ?? 2)
        height: Math.max(2, selectedClient?.lastIpcObject.size[1] ?? 2)
        paintCursor: false
        onHasContentChanged: if (hasContent && root.capturing && root.application) root.save(windowCopy, true)
        onStopped: if (root.capturing) { root.capturing=false; root.error=I18n.t("Failed to capture window. Ensure the window is open."); }
    }
    Timer { id: liveTimer; interval: 150; onTriggered: { screenCopy.live=false; if (screenCopy.hasContent) root.save(screenCopy,false); else { root.capturing=false; root.error=I18n.t("Failed to capture screen."); } } }
    Timer { interval: 5000; running: root.capturing; onTriggered: { root.capturing=false; root.error=I18n.t("Capture timed out."); } }

    Item {
        id: decoration
        anchors.fill: parent
        visible: !root.capturing
        Rectangle { visible:!root.liveAdjust; width:parent.width; height:root.ry; color:"#88000000" }
        Rectangle { visible:!root.liveAdjust; y:root.ry; width:root.rx; height:root.rh; color:"#88000000" }
        Rectangle { visible:!root.liveAdjust; x:root.rx+root.rw; y:root.ry; width:Math.max(0,parent.width-x); height:root.rh; color:"#88000000" }
        Rectangle { visible:!root.liveAdjust; y:root.ry+root.rh; width:parent.width; height:Math.max(0,parent.height-y); color:"#88000000" }
        Rectangle {
            x: root.rx-2; y: root.ry-2; width: Math.max(0,root.rw)+4; height: Math.max(0,root.rh)+4
            color: "transparent"; radius: root.liveAdjust ? 0 : root.application ? 12 : 5; border.width: 2; border.color: Colours.palette.m3primary
            visible:!root.liveAdjust
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.CrossCursor
            property real startX
            property real startY
            property bool dragged: false
            property bool moving: false
            property real originX
            property real originY
            property real originWidth
            property real originHeight
            onPositionChanged: event => {
                if (!root.current) root.loader.selectedOutput = root.screen.name;
                if (pressed && !root.application) {
                    if (Math.abs(event.x-startX)+Math.abs(event.y-startY)>5) {
                        dragged=true; root.selectedClient=null;
                        if (moving) {
                            root.sx=Math.max(0,Math.min(root.width-originWidth,originX+event.x-startX));
                            root.sy=Math.max(0,Math.min(root.height-originHeight,originY+event.y-startY));
                            root.ex=root.sx+originWidth; root.ey=root.sy+originHeight;
                        } else {
                            root.sx=startX; root.sy=startY; root.ex=Math.max(0,Math.min(root.width,event.x)); root.ey=Math.max(0,Math.min(root.height,event.y));
                        }
                    }
                } else root.hover(event.x,event.y);
            }
            onPressed: event => {
                startX=event.x; startY=event.y; dragged=false;
                moving=root.selected && event.x>=root.rx && event.y>=root.ry && event.x<=root.rx+root.rw && event.y<=root.ry+root.rh;
                originX=root.rx;originY=root.ry;originWidth=root.rw;originHeight=root.rh;
            }
            onReleased: {
                const x=root.rx,y=root.ry,w=root.rw,h=root.rh;
                root.sx=x;root.sy=y;root.ex=x+w;root.ey=y+h;
                root.selected=true;
            }
        }
        Repeater {
            model: root.selected && !root.application && !root.liveAdjust ? 4 : 0
            delegate: Rectangle {
                id: handle
                required property int index
                width: 14; height: 14; radius: 7
                color: Colours.palette.m3primary
                x: (index % 2 ? root.rx+root.rw : root.rx)-7
                y: (index >= 2 ? root.ry+root.rh : root.ry)-7
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: (handle.index===0 || handle.index===3) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                    onPositionChanged: event => {
                        if (!pressed) return;
                        const p=mapToItem(root,event.x,event.y);
                        const x=Math.max(0,Math.min(root.width,p.x)), y=Math.max(0,Math.min(root.height,p.y));
                        if (handle.index % 2) root.ex=x; else root.sx=x;
                        if (handle.index >= 2) root.ey=y; else root.sy=y;
                    }
                }
            }
        }
    }
    Elevation {
        z: 1
        anchors.fill: toolbar
        radius: toolbar.radius
        level: 4
        visible: toolbar.visible
    }
    Rectangle {
        id: toolbar
        z: 2
        visible: root.current && !root.capturing && !root.liveAdjust
        width: Math.min(root.width-40, 760)
        height: controls.implicitHeight+38
        x: (root.width-width)/2
        y: root.height-height-40
        radius: 26
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant,0.55)
        Rectangle {
            width:32; height:4; radius:2
            anchors.horizontalCenter:parent.horizontalCenter
            y:7; color:Qt.alpha(Colours.palette.m3onSurfaceVariant,0.25)
        }
        MouseArea {
            x:parent.width/2-48; y:0; width:96; height:17
            cursorShape:Qt.SizeAllCursor
            drag.target:toolbar
            drag.minimumX:20; drag.maximumX:root.width-toolbar.width-20
            drag.minimumY:20; drag.maximumY:root.height-toolbar.height-20
        }
        ColumnLayout {
            id: controls
            anchors.left:parent.left; anchors.right:parent.right
            anchors.top:parent.top
            anchors.leftMargin:20; anchors.rightMargin:20; anchors.topMargin:22
            spacing:14
            RowLayout {
                Layout.fillWidth:true
                spacing:12
                Rectangle {
                    width:42; height:42; radius:14
                    color:Colours.palette.m3primaryContainer
                    MaterialIcon { anchors.centerIn:parent; text:root.loader.ocr?"document_scanner":root.loader.video?"videocam":"photo_camera"; color:Colours.palette.m3onPrimaryContainer; fontStyle:Tokens.font.icon.large }
                }
                ColumnLayout {
                    Layout.fillWidth:true; Layout.minimumWidth:0; spacing:2
                    StyledText { Layout.fillWidth:true; text:root.loader.ocr?I18n.t("Extract text from screen"):I18n.t("Capture screen"); elide:Text.ElideRight; font:Tokens.font.title.medium }
                    StyledText { Layout.fillWidth:true; text:root.loader.ocr?I18n.t("Turkish + English · Indents and spacing preserved"):root.loader.recording.busy?I18n.t("Recording in progress…"):root.loader.recording.recording?I18n.t("Adjust selection or manage recording"):I18n.t("Click window, draw area or select app"); elide:Text.ElideRight; color:Colours.palette.m3onSurfaceVariant; font:Tokens.font.label.small }
                }
                Rectangle {
                    visible:root.loader.recording.recording
                    implicitWidth:statusRow.implicitWidth+24; implicitHeight:32; radius:16
                    color:Qt.alpha(Colours.palette.m3error,0.12)
                    Row {
                        id:statusRow
                        anchors.centerIn:parent; spacing:8
                        Rectangle { width:7; height:7; radius:4; anchors.verticalCenter:parent.verticalCenter; color:Colours.palette.m3error }
                        StyledText { text:(root.loader.recording.paused?I18n.t("Paused · "):"REC · ")+Math.floor(root.loader.recording.elapsed/60)+":"+String(root.loader.recording.elapsed%60).padStart(2,"0"); color:Colours.palette.m3error; font:Tokens.font.label.small }
                    }
                }
                IconButton { icon:"close"; type:IconButton.Text; onClicked:root.loader.dismiss(); Accessible.name:I18n.t("Close capture") }
            }
            RowLayout {
                Layout.fillWidth:true
                spacing:8
                Rectangle {
                    visible:!root.loader.ocr
                    implicitWidth:modeRow.implicitWidth+8; implicitHeight:44; radius:16
                    color:Colours.palette.m3surfaceContainerHigh
                    Row {
                        id:modeRow; anchors.centerIn:parent; spacing:4
                        TextButton { text:I18n.t("Photo"); isToggle:true; checked:!root.loader.video; type:root.loader.video?TextButton.Text:TextButton.Filled; onClicked:root.loader.video=false; Accessible.name:text }
                        TextButton { text:I18n.t("Video"); isToggle:true; checked:root.loader.video; type:root.loader.video?TextButton.Filled:TextButton.Text; onClicked:root.loader.video=true; Accessible.name:text }
                    }
                }
                Item { Layout.fillWidth:true }
                TextButton { text:I18n.t("Area / window"); isToggle:true; checked:!root.application; type:root.application?TextButton.Text:TextButton.Tonal; onClicked:{root.application=false;root.appListOpen=false;root.selected=false;} }
                TextButton { text:I18n.t("Application"); isToggle:true; checked:root.application; type:root.application?TextButton.Tonal:TextButton.Text; onClicked:{root.application=true;root.appListOpen=!root.appListOpen;if(root.appListOpen) search.forceActiveFocus();} }
            }
            Rectangle { Layout.fillWidth:true; implicitHeight:1; color:Qt.alpha(Colours.palette.m3outlineVariant,0.45) }
            RowLayout {
                Layout.fillWidth:true; spacing:10
                Rectangle {
                    visible:root.application
                    Layout.fillWidth:true; implicitHeight:42; radius:14
                    color:Colours.palette.m3surfaceContainerHigh
                    RowLayout {
                        anchors.fill:parent; anchors.leftMargin:12; anchors.rightMargin:10; spacing:10
                        Item {
                            implicitWidth:22; implicitHeight:22
                            readonly property string appIcon:DesktopEntries.heuristicLookup(root.selectedClient?.lastIpcObject.class ?? "")?.icon ?? ""
                            IconImage { anchors.fill:parent; visible:parent.appIcon!=="" && Quickshell.hasThemeIcon(parent.appIcon); source:visible?Quickshell.iconPath(parent.appIcon):"" }
                            MaterialIcon { anchors.centerIn:parent; visible:parent.appIcon==="" || !Quickshell.hasThemeIcon(parent.appIcon); text:"select_window"; color:Colours.palette.m3primary }
                        }
                        StyledText { Layout.fillWidth:true; text:root.selectedClient?.title || I18n.t("Select application"); elide:Text.ElideRight; font:Tokens.font.label.medium }
                        MaterialIcon { text:root.appListOpen?"expand_less":"expand_more"; color:Colours.palette.m3onSurfaceVariant }
                    }
                    StateLayer { radius:parent.radius; onClicked:{root.appListOpen=!root.appListOpen;if(root.appListOpen) search.forceActiveFocus();} }
                    Accessible.role:Accessible.Button
                    Accessible.name:I18n.t("Select application to capture")
                    Accessible.onPressAction:{root.appListOpen=true;search.forceActiveFocus();}
                }
                TextButton { visible:!root.application; text:I18n.t("Full screen"); type:TextButton.Tonal; onClicked:{root.sx=root.sy=0;root.ex=root.width;root.ey=root.height;root.selected=true;root.selectedClient=null;} }
                IconButton { visible:!root.application; icon:"crop_free"; type:IconButton.Text; onClicked:root.selected=false; Accessible.name:I18n.t("Select new area") }
                StyledText { visible:!root.application; Layout.fillWidth:true; text:Math.floor(root.rw)+" × "+Math.floor(root.rh); color:Colours.palette.m3onSurfaceVariant; font:Tokens.font.label.medium }
                IconButton { visible:root.loader.video && !root.loader.recording.recording; icon:root.loader.sound?"volume_up":"volume_off"; type:IconButton.Tonal; onClicked:root.loader.sound=!root.loader.sound; Accessible.name:root.loader.sound?I18n.t("Mute system audio"):I18n.t("Unmute system audio") }
                IconButton { visible:root.loader.recording.recording; icon:root.loader.recording.paused?"play_arrow":"pause"; disabled:root.loader.recording.busy; type:IconButton.Tonal; onClicked:{if(root.loader.recording.paused) root.resume(); else {root.loader.recording.setPaused(true);root.loader.hideForCapture();}} Accessible.name:root.loader.recording.paused?I18n.t("Resume recording from selected area"):I18n.t("Pause recording") }
                TextButton { visible:root.loader.recording.recording; text:I18n.t("Finish"); disabled:root.loader.recording.busy; type:TextButton.Tonal; onClicked:{root.loader.recording.stop();root.loader.hideForCapture();} }
                TextButton { text:root.loader.ocr?I18n.t("Copy text"):root.loader.video?(root.loader.recording.recording?I18n.t("Apply selection"):I18n.t("Start recording")):I18n.t("Take photo"); disabled:root.loader.recording.busy || root.loader.saver.running || (root.application && !root.selectedClient); onClicked:root.capture(); Accessible.name:text }
            }
            StyledText {
                Layout.fillWidth:true
                text:root.error || root.loader.recording.error || (root.loader.ocr?I18n.t("Drag selection · Resize from corners · Enter: copy · Esc: cancel"):root.application?I18n.t("Only selected application is captured even if obscured."):I18n.t("Super+Alt+arrows: resize · Super+Shift+arrows: move"))
                color:(root.error || root.loader.recording.error)?Colours.palette.m3error:Colours.palette.m3onSurfaceVariant
                font:Tokens.font.label.small; wrapMode:Text.Wrap
            }
        }
    }
    Elevation { z:3; anchors.fill:appPanel; radius:appPanel.radius; level:4; visible:appPanel.visible }
    Rectangle {
        id: appPanel
        z:4
        visible:root.current && root.application && root.appListOpen && !root.capturing && !root.liveAdjust
        width:Math.min(toolbar.width,520)
        height:Math.min(400, appColumn.implicitHeight+32)
        x:Math.min(root.width-width-20,toolbar.x)
        y:Math.max(20,toolbar.y-height-12)
        radius:24
        color:Colours.palette.m3surfaceContainerHigh
        border.width:1; border.color:Qt.alpha(Colours.palette.m3outlineVariant,0.6)
        ColumnLayout {
            id:appColumn
            anchors.fill:parent; anchors.margins:16; spacing:12
            RowLayout {
                Layout.fillWidth:true
                MaterialIcon { text:"select_window"; color:Colours.palette.m3primary }
                StyledText { text:I18n.t("Select application"); font:Tokens.font.title.small; Layout.fillWidth:true }
                IconButton { icon:"close"; type:IconButton.Text; onClicked:{root.appListOpen=false;root.forceActiveFocus();} Accessible.name:I18n.t("Close application list") }
            }
            Rectangle {
                Layout.fillWidth:true; implicitHeight:42; radius:14
                color:Colours.palette.m3surfaceContainerHighest
                MaterialIcon { x:12; anchors.verticalCenter:parent.verticalCenter; text:"search"; color:Colours.palette.m3onSurfaceVariant }
                TextFieldBase {
                    id:search
                    anchors.fill:parent; anchors.leftMargin:44; anchors.rightMargin:12
                    placeholderText:I18n.t("Search windows or applications…")
                    text:root.filter
                    onTextEdited:root.filter=text
                    Accessible.name:I18n.t("Search applications")
                    Keys.onDownPressed:{appList.currentIndex=Math.min(appList.count-1,appList.currentIndex+1);}
                    Keys.onUpPressed:{appList.currentIndex=Math.max(0,appList.currentIndex-1);}
                    Keys.onReturnPressed:{if(root.filteredApps.length)root.chooseApp(root.filteredApps[Math.max(0,appList.currentIndex)]);}
                    Keys.onEscapePressed:{root.appListOpen=false;root.forceActiveFocus();}
                }
            }
            ListView {
                id:appList
                Layout.fillWidth:true
                Layout.preferredHeight:Math.min(250,Math.max(64,contentHeight))
                clip:true; spacing:4
                model:root.filteredApps
                currentIndex:0
                delegate:Rectangle {
                    id:appRow
                    required property var modelData
                    required property int index
                    readonly property bool chosen:root.selectedClient===modelData
                    width:appList.width; height:62; radius:14
                    color:chosen?Colours.palette.m3secondaryContainer:appList.currentIndex===index?Qt.alpha(Colours.palette.m3onSurface,0.06):"transparent"
                    RowLayout {
                        anchors.fill:parent; anchors.leftMargin:12; anchors.rightMargin:14; spacing:12
                        Item {
                            implicitWidth:30; implicitHeight:30
                            readonly property string appIcon:DesktopEntries.heuristicLookup(appRow.modelData.lastIpcObject.class)?.icon ?? ""
                            IconImage { anchors.fill:parent; visible:parent.appIcon!=="" && Quickshell.hasThemeIcon(parent.appIcon); source:visible?Quickshell.iconPath(parent.appIcon):"" }
                            MaterialIcon { anchors.centerIn:parent; visible:parent.appIcon==="" || !Quickshell.hasThemeIcon(parent.appIcon); text:"select_window"; color:Colours.palette.m3primary }
                        }
                        ColumnLayout {
                            Layout.fillWidth:true; spacing:3
                            StyledText { Layout.fillWidth:true; text:appRow.modelData.title; elide:Text.ElideRight; font:Tokens.font.label.medium }
                            StyledText { Layout.fillWidth:true; text:appRow.modelData.lastIpcObject.class; elide:Text.ElideRight; color:Colours.palette.m3onSurfaceVariant; font:Tokens.font.label.small }
                        }
                        MaterialIcon { visible:appRow.chosen; text:"check_circle"; color:Colours.palette.m3primary }
                    }
                    StateLayer { radius:parent.radius; onClicked:root.chooseApp(appRow.modelData) }
                    Accessible.role:Accessible.ListItem
                    Accessible.name:modelData.title
                    Accessible.selected:chosen
                    Accessible.onPressAction:root.chooseApp(modelData)
                }
                StyledText { anchors.centerIn:parent; visible:appList.count===0; text:I18n.t("No matching applications"); color:Colours.palette.m3onSurfaceVariant }
            }
        }
    }
}
