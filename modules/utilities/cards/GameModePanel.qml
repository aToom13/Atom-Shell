pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import QtQml.Models
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus
import qs.modules.nexus.common

StyledRect {
    id: root
    required property var props
    required property ScreenState screenState
    property bool advanced: false
    readonly property var render: GameProfiles.profile?.render ?? ({})
    readonly property bool editable: !!GameProfiles.profile && !GameProfiles.busy && !GameProfiles.testRunning
    readonly property bool generating: (render.frameGeneration ?? 1) !== 1
    readonly property real measuredFps: GameProfiles.lastGameFps ?? 0
    readonly property real refreshRate: Hypr.focusedMonitor?.lastIpcObject.refreshRate ?? 0
    readonly property int requestedMultiplier: Number(render.frameGeneration ?? 1)
    readonly property int effectiveMultiplier: requestedMultiplier === 0 && measuredFps > 0 && refreshRate > 0
        ? Math.max(1, Math.min(3, Math.floor(refreshRate / measuredFps))) : Math.max(1, requestedMultiplier)
    readonly property real projectedFps: measuredFps * effectiveMultiplier
    readonly property string artifactHint: {
        if (!generating || measuredFps <= 0 || refreshRate <= 0)
            return "";
        if (requestedMultiplier >= 3)
            return qsTr("Kaynak %1 FPS. 3× kırılmayı artırır; Otomatik veya 2× dene.").arg(Math.round(measuredFps));
        if (requestedMultiplier === 2 && projectedFps < refreshRate * 0.9)
            return qsTr("Kaynak %1 FPS. 2× sınırda; Otomatik veya Kapalı daha temiz.").arg(Math.round(measuredFps));
        return "";
    }
    readonly property var applications: {
        const live = GameProfiles.windows.filter(item => item.appClass !== "gamescope" && (item.isGame || GameProfiles.profiles.some(p => p.appClass === item.appClass && p.isGame)));
        return [{ name: qsTr("Açık uygulama seç…"), key: "" }, ...live];
    }

    implicitHeight: Math.min(options.implicitHeight + heading.implicitHeight + Tokens.padding.large * 2 + Tokens.spacing.medium, 660, screenState.modelData.height - 240)
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    onVisibleChanged: if (visible) GameProfiles.run("status")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            id: heading
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: qsTr("Oyun modu"); font: Tokens.font.body.medium }
            StyledText { text: GameMode.busy ? qsTr("Uygulanıyor…") : GameMode.enabled ? qsTr("Etkin") : qsTr("Kapalı"); color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.label.small }
            StyledSwitch {
                checked: GameMode.enabled
                disabled: !GameMode.ready || GameMode.busy || GameProfiles.busy
                onToggled: GameMode.setEnabled(checked)
                Accessible.name: qsTr("Oyun modunu aç veya kapat")
            }
            IconButton {
                icon: "expand_more"; type: IconButton.Text; padding: Tokens.padding.small
                onClicked: root.props.gameModeExpanded = false
                Accessible.name: qsTr("Oyun panelini kapat")
            }
        }

        Flickable {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: options.implicitHeight
            QQC.ScrollBar.vertical: StyledScrollBar { flickable: scroll }
            ColumnLayout {
                id: options
                width: scroll.width - Tokens.padding.small
                spacing: Tokens.spacing.medium

                Note {
                    visible: !!GameMode.error || !!GameProfiles.error
                    text: GameMode.error || GameProfiles.error
                    color: Colours.palette.m3error
                    Accessible.role: Accessible.AlertMessage
                }
                RowLayout {
                    Layout.fillWidth: true
                    Picker {
                        label: qsTr("Oyun veya uygulama")
                        entries: root.applications
                        selectedKey: GameProfiles.selected
                        enabled: !GameMode.enabled && !GameMode.busy && !GameProfiles.busy && !GameProfiles.testRunning && !GameProfiles.captureRunning
                        onChosen: key => GameProfiles.select(key)
                    }
                    IconButton {
                        Layout.alignment: Qt.AlignBottom
                        icon: "refresh"; type: IconButton.Text; padding: Tokens.padding.small
                        disabled: GameProfiles.busy
                        onClicked: GameProfiles.run("status")
                        Accessible.name: qsTr("Uygulama listesini yenile")
                    }
                }
                ColumnLayout {
                    visible: !!GameProfiles.profile
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    StyledText { text: qsTr("Kare üretimi"); font: Tokens.font.body.small }
                    RowLayout {
                        Layout.fillWidth: true
                        Repeater {
                            model: [1, 0, 2, 3]
                            TextButton {
                                required property int modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                text: modelData === 1 ? qsTr("Kapalı") : modelData === 0 ? qsTr("Otomatik") : modelData + "×"
                                isToggle: true
                                checked: (root.render.frameGeneration ?? 1) === modelData
                                disabled: !root.editable || (modelData > 0 && modelData > (GameProfiles.capabilities.maxMultiplier ?? 1))
                                onClicked: GameProfiles.configure("frameGeneration", modelData)
                                Accessible.name: modelData === 1 ? qsTr("Kare üretimini kapat") : modelData === 0 ? qsTr("Otomatik kare üretimi") : qsTr("%1 kat kare üretimi").arg(modelData)
                            }
                        }
                    }
                    Note {
                        visible: !!root.artifactHint
                        color: Colours.palette.m3error
                        text: root.artifactHint
                    }
                    Note {
                        visible: !GameProfiles.capabilities.frameGeneration
                        text: qsTr("Kare üretimi kullanılamıyor.")
                        color: Colours.palette.m3error
                    }
                }
                IconTextButton {
                    visible: !!GameProfiles.profile && GameProfiles.selected !== "test-cube"
                    Layout.fillWidth: true
                    icon: GameProfiles.captureRunning ? "stop" : "play_arrow"
                    text: GameProfiles.captureRunning ? qsTr("Kare üretimini durdur") : qsTr("Seçili uygulamada başlat")
                    disabled: !GameProfiles.captureRunning && (!root.editable || !GameProfiles.capabilities.liveCapture || !root.generating)
                    onClicked: {
                        if (GameProfiles.captureRunning)
                            GameProfiles.stopCapture();
                        else {
                            root.screenState.utilities = false;
                            GameProfiles.startCapture();
                        }
                    }
                }
                Note {
                    visible: GameProfiles.captureRunning
                    text: !GameProfiles.captureInfo?.ready ? qsTr("Pencereye bağlanılıyor…")
                        : !GameProfiles.captureInfo.active ? qsTr("Beklemede. Uygulamaya dönünce devam eder.")
                        : GameProfiles.captureStats ? qsTr("Yakalama: %1 FPS · Gönderilen: %2 FPS · %3×").arg(Math.round(GameProfiles.captureStats.rendered)).arg(Math.round(GameProfiles.captureStats.shown)).arg(GameProfiles.captureStats.multiplier)
                        : GameProfiles.captureStatsTimedOut ? qsTr("Kare üretimi etkin; istatistik yok.")
                        : qsTr("İstatistik bekleniyor…")
                }
                Note {
                    visible: !!GameProfiles.captureWarning
                    color: Colours.palette.m3error
                    text: GameProfiles.captureWarning
                }
                IconTextButton {
                    Layout.fillWidth: true
                    icon: "deployed_code"
                    text: GameProfiles.testRunning ? qsTr("3D test çalışıyor…") : qsTr("3D küple dene")
                    disabled: GameProfiles.busy || GameProfiles.testRunning || GameProfiles.captureRunning || !GameProfiles.capabilities.testCube || (!GameProfiles.profile && (GameMode.enabled || GameMode.busy))
                    onClicked: GameProfiles.testCube()
                }
                Note {
                    visible: !!GameProfiles.testSummary
                    text: GameProfiles.testSummary
                }
                ColumnLayout {
                    visible: !!GameProfiles.profile
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    HudSwitch { label: qsTr("Oyun içi gösterge"); setting: "hudEnabled"; defaultValue: true }
                    ColumnLayout {
                        visible: root.render.hudEnabled ?? true
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small
                        HudSwitch { label: qsTr("Gerçek oyun FPS’si"); setting: "hudFps"; defaultValue: true }
                        HudSwitch { label: qsTr("CPU kullanımı"); setting: "hudCpu" }
                        HudSwitch { label: qsTr("RAM kullanımı"); setting: "hudRam" }
                        HudSwitch { label: qsTr("CPU sıcaklığı"); setting: "hudTemperature" }
                        Picker {
                            label: qsTr("Gösterge konumu")
                            enabled: root.editable
                            selectedKey: root.render.hudPosition ?? "top-right"
                            entries: [ { name: qsTr("Sağ üst"), key: "top-right" }, { name: qsTr("Sol üst"), key: "top-left" },
                                { name: qsTr("Sağ alt"), key: "bottom-right" }, { name: qsTr("Sol alt"), key: "bottom-left" } ]
                            onChosen: key => GameProfiles.configure("hudPosition", key)
                        }
                        NumberOption { label: qsTr("Yazı boyutu"); setting: "hudFontSize"; minimum: 12; maximum: 28; defaultValue: 16 }
                        NumberOption { label: qsTr("Kenardan uzaklık"); setting: "hudMargin"; maximum: 200; defaultValue: 16 }
                    }
                }
                IconTextButton {
                    visible: !!GameProfiles.profile
                    Layout.fillWidth: true
                    type: IconTextButton.Text
                    icon: root.advanced ? "expand_less" : "tune"
                    text: qsTr("Gelişmiş ayarlar")
                    onClicked: root.advanced = !root.advanced
                }
                ColumnLayout {
                    visible: root.advanced && !!GameProfiles.profile
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    NumberOption { label: qsTr("En düşük kaynak FPS"); setting: "frameGenerationMinFps"; maximum: 120 }
                    Picker {
                        label: qsTr("Kare üretimi gecikmesi")
                        enabled: root.editable
                        selectedKey: root.render.frameGenerationLatency ?? "normal"
                        entries: [ { name: qsTr("Normal · daha akıcı, bir kare gecikme"), key: "normal" },
                            { name: qsTr("Düşük · daha az gecikme, takılma riski"), key: "low" } ]
                        onChosen: key => GameProfiles.configure("frameGenerationLatency", key)
                    }
                    Picker {
                        label: qsTr("Hareket çözünürlüğü")
                        enabled: root.editable
                        selectedKey: String(root.render.flowScale ?? 0.5)
                        entries: [ { name: "0.25", key: "0.25" }, { name: "0.5", key: "0.5" },
                            { name: "0.75", key: "0.75" }, { name: "1.0", key: "1" } ]
                        onChosen: key => GameProfiles.configure("flowScale", parseFloat(key))
                    }
                    IconTextButton {
                        Layout.fillWidth: true
                        icon: "settings"
                        text: qsTr("Güç, görünüm ve bildirim ayarları")
                        onClicked: {
                            root.screenState.utilities = false;
                            WindowFactory.createForPage(PageRegistry.gameModePageIndex);
                        }
                    }
                }
            }
        }
    }

    component Note: StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font: Tokens.font.body.small
        color: Colours.palette.m3onSurfaceVariant
    }
    component Picker: ColumnLayout {
        id: picker
        required property string label
        required property var entries
        required property string selectedKey
        property var choices: []
        signal chosen(key: string)
        Layout.fillWidth: true
        StyledText { text: picker.label; font: Tokens.font.body.small }
        SplitButton {
            id: button
            Layout.fillWidth: true
            type: SplitButton.Tonal
            disabled: !picker.enabled
            menuItems: picker.choices
            active: picker.choices.find(item => item.key === picker.selectedKey) ?? picker.choices[0] ?? null
            minLeftWidth: Math.max(0, picker.width - expandBtn.implicitWidth - spacing)
            label.elide: Text.ElideRight
            label.Layout.preferredWidth: Math.min(label.implicitWidth, picker.width - expandBtn.implicitWidth - horizontalPadding * 2 - 40)
            stateLayer.onClicked: expanded = !expanded
            menu.boundsItem: root
            menu.autoSelect: false
            menu.onItemSelected: item => picker.chosen(item.key)
            Accessible.name: picker.label
        }
        Instantiator {
            model: picker.entries
            delegate: MenuItem {
                required property var modelData
                property string key: modelData.key
                text: modelData.name
            }
            onObjectAdded: (index, object) => picker.choices = [...picker.choices.slice(0, index), object, ...picker.choices.slice(index)]
            onObjectRemoved: (index, object) => picker.choices = picker.choices.filter(item => item !== object)
        }
    }
    component NumberOption: RowLayout {
        id: numberOption
        required property string label
        required property string setting
        required property int maximum
        property int minimum: 0
        property int defaultValue: 0
        Layout.fillWidth: true
        enabled: root.editable
        StyledText { Layout.fillWidth: true; text: numberOption.label; wrapMode: Text.Wrap; font: Tokens.font.body.small }
        StyledSpinBox {
            from: numberOption.minimum; to: numberOption.maximum; stepSize: 1
            value: root.render[numberOption.setting] ?? numberOption.defaultValue
            onValueModified: GameProfiles.configure(numberOption.setting, Math.round(value))
            Accessible.name: numberOption.label
        }
    }
    component HudSwitch: RowLayout {
        id: option
        required property string label
        required property string setting
        property bool defaultValue: false
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: option.label; font: Tokens.font.body.small; wrapMode: Text.Wrap }
        StyledSwitch {
            checked: root.render[option.setting] ?? option.defaultValue
            disabled: !root.editable
            onToggled: GameProfiles.configure(option.setting, checked)
            Accessible.name: option.label
        }
    }
}
