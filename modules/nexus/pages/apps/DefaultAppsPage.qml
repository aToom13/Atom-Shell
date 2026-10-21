pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root
    property list<var> associations: []
    property string selectedKey
    property string errorText
    readonly property bool busy: listing.running || writer.running
    readonly property list<string> helper: ["python3", Paths.toLocalFile(Qt.resolvedUrl("../../../../utils/default_apps.py"))]
    title: qsTr("Default app associations")
    isSubPage: true
    Component.onCompleted: listing.running = true

    function appName(id: string): string {
        return DesktopEntries.applications.values.find(app => app.id + ".desktop" === id)?.name || id || qsTr("Not set");
    }

    property Process listProcess: Process {
        id: listing
        command: [...root.helper, "list"]
        stdout: StdioCollector { onStreamFinished: { try { root.associations = JSON.parse(text); } catch (error) { root.errorText = qsTr("Could not read default applications"); } } }
        stderr: StdioCollector { id: listError }
        onExited: code => { if (code) root.errorText = listError.text.trim(); }
    }
    property Process writeProcess: Process {
        id: writer
        stderr: StdioCollector { id: writeError }
        onExited: code => {
            if (code) root.errorText = writeError.text.trim();
            else { root.errorText = ""; root.selectedKey = ""; listing.running = true; }
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2
        StyledText {
            Layout.fillWidth: true
            text: qsTr("Choose the apps used to open files and links across your desktop.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap
        }
        StyledText { Layout.fillWidth: true; visible: root.errorText !== ""; text: root.errorText; color: Colours.palette.m3error; wrapMode: Text.WordWrap }
        SectionHeader { text: qsTr("File types and links") }
        Repeater {
            model: root.associations
            NavRow {
                required property var modelData
                required property int index
                first: index === 0
                last: index === root.associations.length - 1
                text: modelData.key
                subtext: root.appName(modelData.current) + (modelData.mixed ? qsTr(" • Other file types use different apps") : "")
                icon: "app_registration"
                disabled: root.busy
                onClicked: root.selectedKey = modelData.key
            }
        }
        SectionHeader { text: qsTr("Another file type or link") }
        RowLayout {
            Layout.fillWidth: true
            StyledTextField {
                id: customMime
                Layout.fillWidth: true
                placeholderText: qsTr("File type")
                supportingText: qsTr("Example: application/zip or x-scheme-handler/tg")
            }
            TextButton { text: qsTr("Choose app"); disabled: root.busy || !customMime.text.trim(); onClicked: root.selectedKey = customMime.text.trim() }
        }
        SectionHeader { visible: root.selectedKey !== ""; text: qsTr("Choose app for %1").arg(root.selectedKey) }
        ConnectedRect {
            Layout.fillWidth: true
            visible: root.selectedKey !== ""
            first: true
            last: true
            implicitHeight: picker.implicitHeight + Tokens.padding.medium * 2
            ColumnLayout {
                id: picker
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small
                StyledTextField { id: search; Layout.fillWidth: true; placeholderText: qsTr("Search apps"); leadingIcon: "search" }
                VerticalFadeListView {
                    id: apps
                    Layout.fillWidth: true
                    Layout.preferredHeight: 240
                    clip: true
                    model: [...DesktopEntries.applications.values].filter(app => app.name.toLowerCase().includes(search.text.toLowerCase())).sort((a, b) => a.name.localeCompare(b.name))
                    delegate: StateLayer {
                        id: appItem
                        required property DesktopEntry modelData
                        anchors.fill: undefined
                        width: apps.width
                        implicitHeight: label.implicitHeight + Tokens.padding.medium * 2
                        onClicked: {
                            if (root.busy) return;
                            writer.command = [...root.helper, "set", root.selectedKey, modelData.id + ".desktop"];
                            writer.running = true;
                        }
                        StyledText { id: label; anchors.fill: parent; anchors.margins: Tokens.padding.medium; text: appItem.modelData.name; elide: Text.ElideRight; font: Tokens.font.body.small }
                    }
                }
                TextButton { text: qsTr("Cancel"); type: TextButton.Text; onClicked: root.selectedKey = "" }
            }
        }
    }
}
