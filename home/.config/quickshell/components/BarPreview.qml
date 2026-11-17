// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   B A R   P R E V I E W                                                  │
// │   the bar's shape, drawn small                                           │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick

import Quickshell
import "../theme"
import "../services"

// A thumbnail of a screen with the island on it, showing only what the island
// settings change: whether the island touches the top edge. The real bar is
// a layer surface and cannot be embedded.
Item {
    id: root

    property bool attached: false

    implicitWidth: 108
    implicitHeight: 62

    // The screen outline, so "attached" has an edge to attach to.
    Rectangle {
        id: screen

        anchors.centerIn: parent
        width: root.width - 12
        height: root.height - 14
        radius: 5
        color: Theme.island
        border.color: Theme.borderIn(QsWindow.window)
        border.width: 1
        clip: true

        readonly property int band: 7
        readonly property int inset: 4
        readonly property int islandWidth: 22

        // The island; cut into the edge when attached.
        Rectangle {
            readonly property bool cut: root.attached

            anchors.horizontalCenter: parent.horizontalCenter
            y: cut ? 0 : screen.inset
            width: screen.islandWidth
            height: screen.band + (cut ? screen.inset : 0)
            radius: height / 2
            topLeftRadius: cut ? 0 : radius
            topRightRadius: cut ? 0 : radius
            color: Theme.accent
        }
    }
}
