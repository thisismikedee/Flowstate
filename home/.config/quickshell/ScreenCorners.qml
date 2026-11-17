// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   S C R E E N   C O R N E R S                                            │
// │   a rounded screen · black over the four corners, never in the way       │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell
import Quickshell.Wayland

import "./theme"
import "./components"

// Four small surfaces rather than one over the whole screen, so the rest of
// the screen is not composited through an extra layer. Above everything, and
// deaf: a click on a corner lands on whatever is under it.
Scope {
    id: root

    required property var screen
    // Whether this screen's bar is the live one.
    required property bool live

    // The top corners are never covered: the island alone never reaches
    // them, and there is no bezel band any more.
    readonly property bool topCovered: false

    Variants {
        model: [
            { top: true, left: true, turn: 0 },
            { top: true, left: false, turn: 90 },
            { top: false, left: false, turn: 180 },
            { top: false, left: true, turn: 270 }
        ]

        PanelWindow {
            id: corner

            required property var modelData

            screen: root.screen
            visible: !(corner.modelData.top && root.topCovered)
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "impasto-corners"
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: corner.modelData.top
                bottom: !corner.modelData.top
                left: corner.modelData.left
                right: !corner.modelData.left
            }
            implicitWidth: Theme.screenRadius
            implicitHeight: Theme.screenRadius
            color: "transparent"
            mask: Region {}

            ScreenCorner {
                anchors.fill: parent
                turn: corner.modelData.turn
            }
        }
    }
}
