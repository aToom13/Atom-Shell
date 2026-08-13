pragma Singleton

import QtQuick

QtObject {
    id: root

    // Kept explicit so global shortcuts can open this page without depending on
    // translated labels.
    readonly property int shortcutsPageIndex: 8

    readonly property list<var> pages: [
        // Appearance
        {
            label: qsTr("Wallpaper & style"),
            icon: "palette",
            description: qsTr("Wallpaper, fonts, colours"),
            category: "appearance"
        },

        // Connectivity
        {
            label: qsTr("Display"),
            icon: "monitor",
            description: qsTr("Outputs, resolution and scale"),
            category: "connectivity"
        },
        {
            label: qsTr("Network"),
            icon: "wifi",
            description: qsTr("Wi-Fi, ethernet, VPN and diagnostics"),
            category: "connectivity"
        },
        {
            label: qsTr("Connected devices"),
            icon: "devices_other",
            description: qsTr("Bluetooth, KDE Connect, USB and LAN"),
            category: "connectivity",
            noFill: true
        },
        {
            label: qsTr("Audio"),
            icon: "volume_up",
            description: qsTr("App volumes, sound devices"),
            category: "connectivity"
        },

        // System
        {
            label: qsTr("Power & lock"),
            icon: "lock_clock",
            description: qsTr("Lock screen, idle, battery and OSD"),
            category: "system"
        },
        {
            label: qsTr("Updates"),
            icon: "system_update",
            description: qsTr("System, AUR and Flatpak updates"),
            category: "system"
        },
        {
            label: qsTr("Plugins"),
            icon: "extension",
            description: qsTr("Hyprland plugin runtime and settings"),
            category: "system"
        },
        {
            label: qsTr("Keyboard shortcuts"),
            icon: "keyboard",
            description: qsTr("Window, workspace and shell controls"),
            category: "system"
        },

        // Shell
        {
            label: qsTr("Panels"),
            icon: "dock_to_bottom",
            description: qsTr("Dashboard, taskbar, launcher, sidebar"),
            category: "shell"
        },
        {
            label: qsTr("Apps"),
            icon: "apps",
            description: qsTr("Default apps, favourites, hidden apps"),
            category: "shell"
        },
        {
            label: qsTr("Services"),
            icon: "build",
            description: qsTr("Poll intervals, lyrics backend"),
            category: "shell"
        },
        {
            label: qsTr("Language & region"),
            icon: "globe",
            description: qsTr("UI language, weather location, display units"),
            category: "shell"
        },

        // About
        {
            label: qsTr("About"),
            icon: "info",
            description: qsTr("System information, credits"),
            category: "about"
        },
    ]
}
