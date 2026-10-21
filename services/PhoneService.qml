pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services
import qs.utils

Singleton {
    id: root

    readonly property string controlCommand: Paths.home + "/.local/bin/phone-control"

    property bool ready: false
    property bool adbReady: false
    property bool kdeReachable: false
    property bool kdePaired: false
    property bool charging: false
    property bool refreshing: false
    property bool fileDragActive: false
    property bool transferRunning: false
    property var pendingTransfers: []
    property var transferHistory: []
    property int battery: -1
    property string mode: "none"
    property string target: ""
    property string deviceName: I18n.t("Phone")
    property string error: ""
    property var transports: ({})
    property bool mediaAvailable: false
    property bool mediaPlaying: false
    property string mediaPackage: ""
    property string mediaTitle: ""
    property string mediaArtist: ""
    property string mediaAlbum: ""
    property string mediaArtUrl: ""
    property real mediaPosition: 0
    property real mediaDuration: 0
    property real mediaBpm: 0
    property int mediaVolumeIndex: 0
    property int mediaMaxVolume: 15
    property string selectedMediaSource: "auto"
    readonly property bool mediaPanelOpen: Screens.screens.some(screen => ShellState.forScreen(screen)?.dashboard ?? false)

    onMediaPanelOpenChanged: {
        if (mediaPanelOpen)
            refreshMedia();
    }

    readonly property real mediaVolume: mediaMaxVolume > 0 ? mediaVolumeIndex / mediaMaxVolume : 0

    readonly property bool usbConnected: transports.usb?.connected ?? false
    readonly property bool usbAvailable: transports.usb?.available ?? false
    readonly property bool localConnected: transports.local?.connected ?? false
    readonly property bool localAvailable: transports.local?.available ?? false
    readonly property bool tailscaleConnected: transports.tailscale?.connected ?? false
    readonly property bool tailscaleAvailable: transports.tailscale?.available ?? false
    readonly property bool hasAdbRoute: adbReady || usbAvailable || localAvailable || tailscaleAvailable
    readonly property bool busy: actionProc.running
    readonly property string modeLabel: mode === "usb" ? "USB" : mode === "local" ? I18n.t("Wi-Fi") : mode === "tailscale" ? "Tailscale" : ""
    readonly property string statusText: {
        if (adbReady)
            return I18n.t("%1 connected · mirror and call control ready", modeLabel);
        if (kdeReachable)
            return I18n.t("KDE Connect connected · ring and share ready");
        if (kdePaired)
            return I18n.t("Phone paired · searching connection routes");
        return error || I18n.t("Waiting for USB, Wi-Fi, Tailscale or Bluetooth connection");
    }

    property string actionTitle: ""

    function refresh(details: bool): void {
        if (statusProc.running)
            return;
        refreshing = true;
        statusProc.command = details ? [controlCommand, "status"] : [controlCommand, "status", "--quick"];
        statusProc.running = true;
    }

    function applyStatus(data: var): void {
        adbReady = data.adb_ready ?? false;
        kdeReachable = data.kdeconnect_reachable ?? false;
        kdePaired = data.kdeconnect_paired ?? false;
        if (data.charging !== null && data.charging !== undefined)
            charging = data.charging;
        if (data.battery !== null && data.battery !== undefined)
            battery = data.battery;
        mode = data.mode ?? "none";
        target = data.target ?? "";
        deviceName = data.device_name || qsTr("Telefon");
        error = data.error ?? "";
        transports = data.transports ?? ({});
        ready = adbReady || kdeReachable;
        if (target)
            refreshMedia();
        else
            mediaAvailable = false;
    }

    function refreshMedia(): void {
        if (!target || mediaStatusProc.running)
            return;
        mediaStatusProc.command = [controlCommand, "media-status", target];
        mediaStatusProc.running = true;
    }

    function applyMedia(data: var): void {
        mediaAvailable = data.available ?? false;
        mediaPlaying = data.playing ?? false;
        mediaPackage = data.package ?? "";
        mediaTitle = data.title ?? "";
        mediaArtist = data.artist ?? "";
        mediaAlbum = data.album ?? "";
        mediaArtUrl = data.art_url ?? "";
        mediaPosition = data.position ?? 0;
        mediaDuration = data.duration ?? 0;
        mediaBpm = data.bpm ?? 0;
        mediaVolumeIndex = data.volume ?? 0;
        mediaMaxVolume = data.max_volume ?? 15;
    }

    function setMediaVolume(value: real): void {
        if (!target || mediaVolumeProc.running)
            return;
        mediaVolumeIndex = Math.round(Math.max(0, Math.min(1, value)) * mediaMaxVolume);
        mediaVolumeProc.command = [controlCommand, "media-volume", mediaVolumeIndex.toString(), target];
        mediaVolumeProc.running = true;
    }

    function controlMedia(action: string): void {
        if (!target || mediaActionProc.running)
            return;
        mediaActionProc.command = [controlCommand, "media-action", action, target];
        mediaActionProc.running = true;
    }

    function seekMedia(position: real): void {
        if (!target || mediaActionProc.running || mediaDuration <= 0)
            return;
        mediaPosition = Math.max(0, Math.min(mediaDuration, position));
        mediaActionProc.command = [controlCommand, "media-seek", mediaPosition.toString(), target];
        mediaActionProc.running = true;
    }

    function runAction(name: string, title: string): void {
        if (actionProc.running) {
            Toaster.toast(qsTr("Telefon işlemi sürüyor"), actionTitle, "hourglass_top");
            return;
        }
        actionTitle = title;
        actionProc.command = [controlCommand, "action", name];
        actionProc.running = true;
    }

    function openMirror(): void {
        Quickshell.execDetached([Paths.home + "/.local/bin/phone-mirror"]);
        Toaster.toast(qsTr("Telefon ekranı açılıyor"), qsTr("scrcpy en hızlı ADB yolunu kullanacak"), "screen_share");
    }

    function sendFiles(urls: var): void {
        if (actionProc.running) {
            Toaster.toast(qsTr("Telefon işlemi sürüyor"), actionTitle, "hourglass_top");
            return;
        }

        const paths = [];
        for (const url of urls) {
            const path = Paths.toLocalFile(url);
            if (path)
                paths.push(path);
        }
        if (!paths.length) {
            Toaster.toast(qsTr("Dosya gönderilemedi"), qsTr("Geçerli bir yerel dosya bırakın"), "error");
            return;
        }

        actionTitle = paths.length === 1 ? qsTr("Dosya telefona gönderildi") : qsTr("Dosyalar telefona gönderildi");
        pendingTransfers = paths;
        transferRunning = true;
        actionProc.command = [controlCommand, "send-file"].concat(paths);
        actionProc.running = true;
    }

    function fileName(path: string): string {
        return path.substring(path.lastIndexOf("/") + 1) || path;
    }

    function openContainingFolder(path: string): void {
        const separator = path.lastIndexOf("/");
        Quickshell.execDetached(["xdg-open", separator > 0 ? path.substring(0, separator) : path]);
    }

    function openLocalSend(): void {
        Quickshell.execDetached(["localsend"]);
        Toaster.toast(qsTr("LocalSend açılıyor"), qsTr("Telefondan bu bilgisayarı seçip dosyayı gönderin"), "send_to_mobile");
    }

    Process {
        id: statusProc

        stdout: StdioCollector { id: statusOutput }
        stderr: StdioCollector { id: statusError }
        onExited: code => {
            root.refreshing = false;
            if (code !== 0) {
                root.error = I18n.t("Could not read phone status");
                if (statusError.text.trim())
                    console.warn("PhoneService status failed:", statusError.text.trim());
                return;
            }
            try {
                root.applyStatus(JSON.parse(statusOutput.text.trim()));
            } catch (error) {
                root.error = I18n.t("Phone status output is invalid");
                console.warn("PhoneService status parse failed:", error);
            }
        }
    }

    Process {
        id: actionProc

        stdout: StdioCollector { id: actionOutput }
        stderr: StdioCollector { id: actionError }
        onExited: code => {
            const output = (code === 0 ? actionOutput.text : actionError.text).trim();
            if (root.transferRunning) {
                const finished = root.pendingTransfers.map(path => ({
                    path: path,
                    name: root.fileName(path),
                    success: code === 0,
                    time: Qt.formatDateTime(new Date(), "HH:mm")
                }));
                root.transferHistory = finished.concat(root.transferHistory).slice(0, 6);
                root.pendingTransfers = [];
                root.transferRunning = false;
            }
            Toaster.toast(
                code === 0 ? root.actionTitle : I18n.t("Phone action failed"),
                output || (code === 0 ? I18n.t("Action completed") : I18n.t("Check phone connection")),
                code === 0 ? "phonelink" : "error"
            );
            root.refresh(true);
        }
    }

    Process {
        id: autoConnectProc

        command: [root.controlCommand, "action", "connect-wireless"]
        onExited: code => {
            if (code === 0)
                root.refresh(true);
        }
    }

    Process {
        id: mediaStatusProc

        stdout: StdioCollector { id: mediaStatusOutput }
        onExited: code => {
            if (code !== 0)
                return;
            try {
                root.applyMedia(JSON.parse(mediaStatusOutput.text.trim()));
            } catch (error) {
                console.warn("PhoneService media parse failed:", error);
            }
        }
    }

    Process {
        id: mediaVolumeProc
        onExited: root.refreshMedia()
    }

    Process {
        id: mediaActionProc
        onExited: root.refreshMedia()
    }

    Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: root.refresh(false)
    }

    Timer {
        interval: 5000
        running: !root.localConnected && !root.tailscaleConnected && (root.localAvailable || root.tailscaleAvailable)
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!autoConnectProc.running)
                autoConnectProc.running = true;
        }
    }

    Timer {
        interval: 3000
        running: root.adbReady && root.mediaPanelOpen
        repeat: true
        onTriggered: root.refreshMedia()
    }

    Timer {
        interval: 1000
        running: root.mediaPlaying && root.mediaDuration > 0
        repeat: true
        onTriggered: root.mediaPosition = Math.min(root.mediaDuration, root.mediaPosition + 1)
    }

    Component.onCompleted: refresh(true)
}
