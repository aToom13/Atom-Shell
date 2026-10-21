pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus

Singleton {
    id: root

    property var windows: []

    function create(parent: Item, props: var): void {
        if (props?.initialPage === PageRegistry.shortcutsPageIndex) {
            const cached = windows.find(window => window.keepAlive);
            if (cached) {
                cached.openShortcuts(props.initialShortcutQuery);
                return;
            }
        }
        const window = nexusComp.createObject(parent ?? dummy, props);
        if (window)
            windows = windows.concat([window]);
    }

    function createForPage(page: int): void {
        create(null, { initialPage: page });
    }

    function createForSubPage(page: int, subPage: int): void {
        create(null, { initialPage: page, initialSubPage: subPage });
    }

    function toggleShortcuts(): void {
        togglePage(PageRegistry.shortcutsPageIndex);
    }

    function togglePage(page: int): void {
        const opened = windows.filter(window => window.visible && window.currentPage === page);
        if (opened.length)
            opened.forEach(window => window.visible = false);
        else
            createForPage(page);
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: {
            if (!root.windows.some(window => window.keepAlive))
                root.create(null, { initialPage: PageRegistry.shortcutsPageIndex, visible: false });
        }
    }

    QtObject {
        id: dummy
    }

    Component {
        id: nexusComp

        FloatingWindow {
            id: win

            property int initialPage
            property int initialSubPage: -1
            property string initialShortcutQuery
            readonly property int currentPage: nexus.nState.currentPageIdx
            readonly property bool keepAlive: initialPage === PageRegistry.shortcutsPageIndex
            Component.onDestruction: root.windows = root.windows.filter(window => window !== win)

            function openShortcuts(query: var): void {
                if (query !== undefined)
                    nexus.nState.shortcutQuery = query;
                nexus.nState.currentPageIdx = PageRegistry.shortcutsPageIndex;
                visible = true;
            }

            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false

            onVisibleChanged: {
                if (!visible && !keepAlive)
                    destroy();
            }

            implicitWidth: nexus.implicitWidth
            implicitHeight: nexus.implicitHeight

            minimumSize.width: contentItem.Tokens.sizes.nexus.minWidth
            minimumSize.height: contentItem.Tokens.sizes.nexus.minHeight

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            title: qsTr("Nexus — %1").arg(PageRegistry.pages[nexus.nState.currentPageIdx].label)

            Nexus {
                id: nexus

                anchors.fill: parent
                nState.screen: win.screen
                nState.isWindow: true
                nState.currentPageIdx: win.initialPage
                nState.shortcutQuery: win.initialShortcutQuery
                Component.onCompleted: {
                    if (win.initialSubPage >= 0)
                        nState.openSubPage(win.initialSubPage);
                }
                onClose: win.visible = false
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
