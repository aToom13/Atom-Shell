pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.services

Singleton {
    id: root

    property string previousSinkName: ""
    property string previousSourceName: ""

    property list<PwNode> sinks: []
    property list<PwNode> sources: []
    property list<PwNode> streams: []
    property var sinkDetails: ({})
    property var streamRoutes: ({})
    property bool routesReady
    property var moveQueue: []
    readonly property list<PwNode> availableSinks: routesReady ? sinks.filter(n => sinkDetails[n.name]?.available === true) : []
    readonly property bool routingBusy: routeProcess.running || moveQueue.length > 0

    function outputName(node: PwNode): string {
        if (!node) return I18n.t("Detecting output…");
        const port = sinkDetails[node.name]?.port;
        if (port === "Speaker") return I18n.t("Speaker");
        if (port === "Headphones") return I18n.t("Headphones");
        return node.nickname || node.description || node.name;
    }

    function outputForNodes(nodes: var): PwNode {
        const name = streamRoutes[nodes[0]?.id]?.sinkName;
        return sinks.find(n => n.name === name) ?? null;
    }

    function moveApp(nodes: var, target: PwNode): void {
        if (routingBusy || !target?.ready || !availableSinks.some(n => n.id === target.id))
            return;
        const moves = [];
        for (const node of nodes) {
            const route = streamRoutes[node?.id];
            if (!node?.ready || !route || String(route.serial) !== String(node.properties["object.serial"])) {
                Toaster.toast(qsTr("Ses çıkışı değiştirilemedi"), qsTr("Uygulamanın ses akışı yenileniyor. Tekrar deneyin."), "error");
                routeRefresh.restart();
                return;
            }
            moves.push({index: route.index, serial: route.serial, nodeId: node.id, target: target.name});
        }
        moveQueue = moves;
        moveNext();
    }

    function moveNext(): void {
        if (!moveQueue.length) {
            routeRefresh.restart();
            return;
        }
        const next = moveQueue[0];
        moveQueue = moveQueue.slice(1);
        const live = streams.find(n => n?.id === next.nodeId && String(n.properties["object.serial"]) === String(next.serial));
        if (!live || !availableSinks.some(n => n.name === next.target)) {
            moveQueue = [];
            Toaster.toast(qsTr("Ses çıkışı değiştirilemedi"), qsTr("Uygulama veya çıkış cihazı artık kullanılabilir değil."), "error");
            return;
        }
        routeProcess.command = ["pactl", "move-sink-input", String(next.index), next.target];
        routeProcess.running = true;
    }

    Timer {
        id: routeRefresh
        interval: 120
        onTriggered: {
            if (routeSnapshot.running) restart();
            else routeSnapshot.running = true;
        }
    }

    Process {
        id: routeSnapshot
        command: ["pactl", "-f", "json", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const details = {};
                    const names = {};
                    for (const sink of data.sinks ?? []) {
                        const port = (sink.ports ?? []).find(p => p.name === sink.active_port);
                        details[sink.name] = {available: port?.availability !== "not available", port: port?.type ?? ""};
                        names[sink.index] = sink.name;
                    }
                    const routes = {};
                    for (const input of data.sink_inputs ?? [])
                        routes[input.properties["object.id"]] = {index: input.index,
                            serial: input.properties["object.serial"], sinkName: names[input.sink]};
                    root.sinkDetails = details;
                    root.streamRoutes = routes;
                    root.routesReady = true;
                } catch (error) {
                    console.warn("Audio routing snapshot:", error);
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) console.warn("pactl audio routing snapshot failed:", exitCode);
        }
    }

    Process {
        id: routeEvents
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (/ on (sink|sink-input|card|server)( #|$)/.test(line))
                    routeRefresh.restart();
            }
        }
        onExited: routeReconnect.restart()
    }

    Timer {
        id: routeReconnect
        interval: 2000
        onTriggered: { routeEvents.running = true; routeRefresh.restart(); }
    }

    Process {
        id: routeProcess
        stderr: StdioCollector { id: routeError }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.moveQueue = [];
                Toaster.toast(qsTr("Ses çıkışı değiştirilemedi"), routeError.text.trim() || qsTr("Ses sunucusu isteği reddetti."), "error");
                routeRefresh.restart();
            } else root.moveNext();
        }
    }

    readonly property var playbackApps: {
        const groups = new Map();
        for (const stream of streams) {
            if (!stream?.ready || stream.properties["media.class"] !== "Stream/Output/Audio"
                    || stream.properties["application.id"] === "com.github.wwmm.easyeffects")
                continue;
            const name = getStreamName(stream);
            const key = stream.properties["application.id"] || stream.properties["application.name"] || stream.name;
            if (!groups.has(key))
                groups.set(key, {key, name, nodes: []});
            groups.get(key).nodes.push(stream);
        }
        return [...groups.values()].sort((a, b) => a.name.localeCompare(b.name));
    }

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property bool muted: !!sink?.audio?.muted
    readonly property real volume: sink?.audio?.volume ?? 0

    readonly property bool sourceMuted: !!source?.audio?.muted
    readonly property real sourceVolume: source?.audio?.volume ?? 0

    readonly property alias cava: cava
    readonly property alias beatTracker: beatTracker

    function setVolume(newVolume: real): void {
        if (sink?.ready && sink?.audio) {
            sink.audio.muted = false;
            sink.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function incrementVolume(amount: real): void {
        setVolume(volume + (amount || GlobalConfig.services.audioIncrement));
    }

    function decrementVolume(amount: real): void {
        setVolume(volume - (amount || GlobalConfig.services.audioIncrement));
    }

    function setSourceVolume(newVolume: real): void {
        if (source?.ready && source?.audio) {
            source.audio.muted = false;
            source.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function incrementSourceVolume(amount: real): void {
        setSourceVolume(sourceVolume + (amount || GlobalConfig.services.audioIncrement));
    }

    function decrementSourceVolume(amount: real): void {
        setSourceVolume(sourceVolume - (amount || GlobalConfig.services.audioIncrement));
    }

    function setAudioSink(newSink: PwNode): void {
        Pipewire.preferredDefaultAudioSink = newSink;
    }

    function setAudioSource(newSource: PwNode): void {
        Pipewire.preferredDefaultAudioSource = newSource;
    }

    function cycleNextAudioOutput(): void {
        if (sinks.length === 0)
            return;

        const currentIndex = sinks.findIndex(s => s === sink);
        const nextIndex = (currentIndex + 1) % sinks.length;
        setAudioSink(sinks[nextIndex]);
    }

    function setStreamVolume(stream: PwNode, newVolume: real): void {
        if (stream?.ready && stream?.audio) {
            stream.audio.muted = false;
            stream.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function setStreamMuted(stream: PwNode, muted: bool): void {
        if (stream?.ready && stream?.audio) {
            stream.audio.muted = muted;
        }
    }

    function getStreamVolume(stream: PwNode): real {
        return stream?.audio?.volume ?? 0;
    }

    function getStreamMuted(stream: PwNode): bool {
        return !!stream?.audio?.muted;
    }

    function getStreamName(stream: PwNode): string {
        if (!stream)
            return qsTr("Unknown");
        // Try application name first, then description, then name
        return stream.properties["application.name"] || stream.description || stream.name || qsTr("Unknown Application");
    }

    function refreshNodes(): void {
        const newSinks = [];
        const newSources = [];
        const newStreams = [];

        for (const node of Pipewire.nodes.values) {
            if (!node.isStream) {
                if (node.isSink)
                    newSinks.push(node);
                else if (node.audio)
                    newSources.push(node);
            } else if (node.audio) {
                newStreams.push(node);
            }
        }

        root.sinks = newSinks;
        root.sources = newSources;
        root.streams = newStreams;
    }

    onSinkChanged: {
        if (!sink?.ready)
            return;

        const newSinkName = sink.description || sink.name || qsTr("Unknown Device");

        if (previousSinkName && previousSinkName !== newSinkName && GlobalConfig.utilities.toasts.audioOutputChanged)
            Toaster.toast(qsTr("Audio output changed"), qsTr("Now using: %1").arg(newSinkName), "volume_up");

        previousSinkName = newSinkName;
    }

    onSourceChanged: {
        if (!source?.ready)
            return;

        const newSourceName = source.description || source.name || qsTr("Unknown Device");

        if (previousSourceName && previousSourceName !== newSourceName && GlobalConfig.utilities.toasts.audioInputChanged)
            Toaster.toast(qsTr("Audio input changed"), qsTr("Now using: %1").arg(newSourceName), "mic");

        previousSourceName = newSourceName;
    }

    // Populate immediately: Pipewire.nodes may already be filled by the time this
    // lazily-loaded singleton is created, so onValuesChanged would never fire.
    Component.onCompleted: {
        refreshNodes();
        routeRefresh.restart();
        previousSinkName = sink?.description || sink?.name || qsTr("Unknown Device");
        previousSourceName = source?.description || source?.name || qsTr("Unknown Device");
    }

    Connections {
        function onValuesChanged(): void {
            root.refreshNodes();
        }

        target: Pipewire.nodes
    }

    // Always track the current defaults so volume/mute bind even if the lists
    // momentarily lag behind the default node.
    PwObjectTracker {
        objects: [root.sink, root.source, ...root.sinks, ...root.sources, ...root.streams].filter(n => n)
    }

    CavaProvider {
        id: cava

        bars: GlobalConfig.services.visualiserBars
    }

    BeatTracker {
        id: beatTracker
    }

    IpcHandler {
        function showOsd(): void { ShellState.componentsForActive()?.panels?.osd.showAudio(); }
        function openMixer(): void { ShellState.componentsForActive()?.panels?.osd.openMixer(); }
        function closeMixer(): void { ShellState.componentsForActive()?.panels?.osd.closeMixer(); }
        function adjustMixer(direction: int): void { ShellState.componentsForActive()?.panels?.osd.adjustSelected(direction > 0 ? 1 : -1); }
        function muteMixer(): void { ShellState.componentsForActive()?.panels?.osd.muteSelected(); }
        function mixerKey(key: string): void { ShellState.componentsForActive()?.panels?.osd.mixer?.handleKey(key); }
        function mixerStatus(): string {
            const panel = ShellState.componentsForActive()?.panels?.osd;
            return JSON.stringify(Object.assign({open: panel?.expanded ?? false, armed: panel?.keyboardArmed ?? false, panelWidth: panel?.width ?? 0,
                visible: panel?.shouldBeActive ?? false}, panel?.mixer?.status() ?? {}));
        }
        function cycleOutput(): void {
            root.cycleNextAudioOutput();
        }

        target: "audio"
    }
}
