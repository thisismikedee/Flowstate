// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   L O C K   I S L A N D                                                  │
// │   the island on the lock · the padlock                                   │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../theme"
import "../services"
import "../components"

// The bar's island, where the bar has it and at its resting size, holding a
// padlock. As the lock lets go the padlock gives way to the bar's own time,
// so the island left on screen is the bar's.
Item {
    id: root

    // For the surface to fade the padlock with the rest of the type while the
    // island itself stays.
    property real held: 1

    readonly property bool attached: SettingsService.notched
    readonly property int notchPad: root.attached ? Theme.barTopMargin : 0

    readonly property int restWidth: ModuleService.restWidth
    readonly property int restHeight: Theme.capsuleHeight + root.notchPad

    anchors.horizontalCenter: parent.horizontalCenter
    y: root.attached ? 0 : Theme.barTopMargin
    width: root.restWidth
    height: root.restHeight

    Behavior on width {
        NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing }
    }
    Behavior on height {
        NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing }
    }

    // ── SHAPE ───────────────────────────────────────────────────────────────

    NotchFillet {
        anchors.right: body.left
        anchors.top: parent.top
        visible: root.attached
        mirrored: true
    }

    NotchFillet {
        anchors.left: body.right
        anchors.top: parent.top
        visible: root.attached
    }

    Rectangle {
        id: body

        anchors.fill: parent
        color: Theme.island
        radius: Math.min(root.height / 2, Theme.radiusLarge + 4)
        topLeftRadius: root.attached ? 0 : body.radius
        topRightRadius: root.attached ? 0 : body.radius

        Behavior on radius {
            NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing }
        }
    }

    // ── CONTENT ─────────────────────────────────────────────────────────────
    //
    // Centred as the bar centres its own: half the notch's pad above, half
    // below.

    Item {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.notchPad / 2
        anchors.top: parent.top
        anchors.topMargin: root.notchPad / 2

        Padlock {
            anchors.centerIn: parent
            scale: 0.8
            opened: LockService.leaving
            tint: Theme.text
            opacity: root.held

            Behavior on scale {
                NumberAnimation { duration: Theme.durationMorph; easing.type: Easing.OutBack }
            }
        }

        // The bar's time, drawn as the bar's clock draws it, arriving as the
        // padlock goes.
        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        Row {
            anchors.centerIn: parent
            spacing: 8
            opacity: 1 - root.held

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Tr.date(clock.date, SettingsService.clockShowsSeconds
                    ? SettingsService.clockFormat.replace("mm", "mm:ss")
                    : SettingsService.clockFormat)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeRegular
                font.weight: Font.DemiBold
                color: Theme.text
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: SettingsService.clockShowsDate
                text: Tr.date(clock.date, "ddd d MMM")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }
        }
    }
}
