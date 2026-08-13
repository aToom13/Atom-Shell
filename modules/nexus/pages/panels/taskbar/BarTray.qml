pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Tray")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Background")
            checked: Config.bar.tray.background
            onToggled: GlobalConfig.bar.tray.background = checked
        }

        ToggleRow {
            text: qsTr("Recolour icons")
            checked: Config.bar.tray.recolour
            onToggled: GlobalConfig.bar.tray.recolour = checked
        }

        ToggleRow {
            text: qsTr("Compact")
            checked: Config.bar.tray.compact
            onToggled: GlobalConfig.bar.tray.compact = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Popout on hover")
            subtext: qsTr("Show the tray menu popout when hovering")
            checked: Config.bar.popouts.tray
            onToggled: GlobalConfig.bar.popouts.tray = checked
        }

        SectionHeader { text: qsTr("Hidden tray icons") }

        InfoRow {
            visible: GlobalConfig.bar.tray.hiddenIcons.length === 0
            first: true
            icon: "visibility"
            label: qsTr("All tray icons are visible")
            subtext: qsTr("Add an icon ID or regular expression below")
            value: ""
        }

        Repeater {
            model: GlobalConfig.bar.tray.hiddenIcons
            delegate: ConnectedRect {
                required property string modelData
                required property int index
                Layout.fillWidth: true
                first: index === 0
                implicitHeight: hiddenLayout.implicitHeight + Tokens.padding.medium * 2
                RowLayout {
                    id: hiddenLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium
                    MaterialIcon { text: "visibility_off"; fontStyle: Tokens.font.icon.small }
                    StyledText { Layout.fillWidth: true; text: modelData; font: Tokens.font.body.small; elide: Text.ElideRight }
                    IconButton { icon: "delete"; type: IconButton.Text; onClicked: GlobalConfig.bar.tray.hiddenIcons = GlobalConfig.bar.tray.hiddenIcons.filter(icon => icon !== modelData) }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            last: true
            implicitHeight: hiddenInputLayout.implicitHeight + Tokens.padding.medium * 2
            RowLayout {
                id: hiddenInputLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium
                StyledTextField { id: hiddenIcon; Layout.fillWidth: true; placeholderText: qsTr("Icon ID or regex"); leadingIcon: "filter_alt"; onAccepted: addHidden() }
                IconTextButton {
                    icon: "add"
                    text: qsTr("Hide")
                    type: ButtonBase.Filled
                    disabled: !hiddenIcon.text.trim()
                    onClicked: addHidden()
                }
            }
        }

        function addHidden(): void {
            const value = hiddenIcon.text.trim();
            if (value && !GlobalConfig.bar.tray.hiddenIcons.includes(value))
                GlobalConfig.bar.tray.hiddenIcons = [...GlobalConfig.bar.tray.hiddenIcons, value];
            hiddenIcon.text = "";
        }
    }
}
