pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    property var folders: []
    property bool loaded

    function normalise(folder: var): var {
        return {
            id: String(folder.id || Date.now()),
            name: String(folder.name || "").trim(),
            icon: String(folder.icon || "folder"),
            apps: Array.isArray(folder.apps) ? folder.apps.map(String) : []
        };
    }

    function save(nextFolders: var): void {
        folders = nextFolders.map(normalise).filter(folder => folder.name && folder.apps.length);
        if (loaded)
            storage.setText(JSON.stringify(folders, null, 2));
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.config}/launcher-folders.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.folders = Array.isArray(data) ? data.map(root.normalise).filter(folder => folder.name && folder.apps.length) : [];
            } catch (error) {
                console.warn(`Unable to parse launcher folders: ${error}`);
            }
            root.loaded = true;
        }
        onLoadFailed: err => {
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText("[]"));
            else
                console.warn(`Unable to load launcher folders: ${err}`);
        }
    }
}
