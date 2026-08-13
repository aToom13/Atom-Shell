pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus

Singleton {
    id: root

    function create(parent: Item, props: var): void {
        nexusComp.createObject(parent ?? dummy, props);
    }

    function createForPage(page: int): void {
        nexusComp.createObject(dummy, { initialPage: page });
    }

    function createForSubPage(page: int, subPage: int): void {
        nexusComp.createObject(dummy, { initialPage: page, initialSubPage: subPage });
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

            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false

            onVisibleChanged: {
                if (!visible)
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
                Component.onCompleted: {
                    if (win.initialSubPage >= 0)
                        nState.openSubPage(win.initialSubPage);
                }
                onClose: win.destroy()
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
