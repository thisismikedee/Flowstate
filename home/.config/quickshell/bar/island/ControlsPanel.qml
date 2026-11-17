// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   C O N T R O L S   P A N E L                                            │
// │   control centre · shortcut row and block grid                           │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Layouts
import Quickshell

import "../../theme"
import "../../services"
import "../../components"
import "../widgets"
import "./controls"

// The control centre: a row of small buttons, when any are chosen, over a
// grid of blocks (`ControlsService.blocks`) that the user arranges like
// desktop widgets.
//
// Right-click the background to arrange: drag blocks from the tray
// (`ControlsTray`, hung under the island by the bar) onto a cell, pull a
// corner or scroll to resize, and drop one back on the tray to remove it.
// Tiles that lead to a list (Wi-Fi, Bluetooth) open it as an island panel of
// its own, sized as a list rather than a block.
ColumnLayout {
    id: root

    signal closed()
    signal panelRequested(string panel)
    // Settings is a window this panel does not own; the request is passed up.
    signal settingsRequested()

    readonly property bool editing: ControlsService.editing

    // True while the island's time is docked in this panel's top row: the
    // panel's own top-row time stays hidden, so the island's time is the
    // only one — but it keeps its place in the row, so the battery does
    // not slide over into its spot. The battery in the top row stays.
    property bool timeDocked: false

    spacing: ControlsService.rowGap

    // Escape leaves arranging first; otherwise it reaches the island, which
    // closes.
    Component.onCompleted: root.forceActiveFocus()

    Keys.onEscapePressed: event => {
        if (!root.editing) {
            event.accepted = false
            return
        }
        ControlsService.edit(false)
    }

    // Closing the panel ends arranging too, so it never reopens still in that
    // mode, swallowing clicks.
    Component.onDestruction: {
        ControlsService.edit(false)
        ControlsService.board = null
    }

    // ── TOP ROW ─────────────────────────────────────────────────────────────
    //
    // The time and the battery on the left, when they are on, and the
    // buttons on the right (`ControlsService.topButtons`), arranged in the
    // settings, or while arranging by choosing the row as a block is chosen.
    // With neither it is laid out only while arranging.

    Item {
        visible: ControlsService.topShown
        Layout.fillWidth: true
        // A Layout nested in a Layout fills by default; without this it takes
        // the grid's height.
        Layout.fillHeight: false
        Layout.preferredHeight: ControlsService.rowHeight

        readonly property bool chosen: ControlsService.selected === "top"

        SystemClock {
            id: openClock

            precision: SettingsService.clockShowsSeconds ? SystemClock.Seconds : SystemClock.Minutes
        }

        RowLayout {
            anchors.fill: parent
            spacing: 12
            // Disabled while arranging, as a block's face is, so a click
            // chooses the row instead of pressing a button.
            enabled: !root.editing

            // The time stays in view while the island is open.
            Row {
                Layout.leftMargin: 4
                Layout.alignment: Qt.AlignVCenter
                spacing: Theme.radiusMedium
                visible: (ControlsService.topClock || ControlsService.topBattery) && !root.editing

                Text {
                    id: topTime

                    // Hidden while the island's time is docked here, but
                    // still laid out: it reserves the time's width, so the
                    // battery keeps its place to the right of the docked
                    // time. Its size matches the island's time at rest, so
                    // the reserved width is exactly the docked time's.
                    visible: ControlsService.topClock || root.timeDocked
                    opacity: root.timeDocked ? 0 : 1
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(openClock.date, SettingsService.clockShowsSeconds
                        ? SettingsService.clockFormat.replace("mm", "mm:ss")
                        : SettingsService.clockFormat)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeRegular
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: Theme.text
                }

                // The battery, drawn flat and 2D and flown in from the
                // centre: on Super+A it spawns around the centre of the
                // expanded state and travels left to land beside the
                // docked time, at the same moment the time docks — both
                // land together in the top row, instead of the battery
                // just appearing. The slot keeps the battery's place in
                // the row, so the layout never shifts; only the visual
                // inside it travels.
                Item {
                    id: batterySlot

                    visible: ControlsService.topBattery
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: batteryFly.width
                    implicitHeight: batteryFly.height

                    // 0 at rest, 1 docked in the top row. A binding, like
                    // the time's `slide`, so it follows `root.timeDocked`
                    // reactively: the battery appears every time the
                    // control centre opens and flows back every time it
                    // closes, whatever the panel's creation timing. It is
                    // gated by `ready`, which flips true once in
                    // `Component.onCompleted`, so a freshly created panel
                    // starts at 0 and flies in (the Behavior animates
                    // the 0→1) rather than being born at 1 with no
                    // motion. A one-shot onCompleted assignment alone
                    // froze `travel` at its creation-time value: if the
                    // panel was created while the control centre was not
                    // yet docked, the battery stayed invisible for that
                    // panel's whole life. On the island's own morph
                    // clock, the same as the time's slide, so the two
                    // land together.
                    property bool ready: false
                    property real travel: batterySlot.ready ? (root.timeDocked ? 1 : 0) : 0

                    Behavior on travel {
                        NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing }
                    }

                    Component.onCompleted: batterySlot.ready = true

                    // The spawn: the visual's centre on the panel's
                    // centre. The slot's final place in the panel is
                    // the row's left margin (4) plus the docked time
                    // and the row's spacing; the panel is `root.width`
                    // wide, so the offset from the slot to the centre
                    // is the centre minus that final place, less half
                    // the visual.
                    readonly property real spawnX: root.width / 2 - 4 - topTime.implicitWidth
                        - Theme.radiusMedium - batteryFly.width / 2

                    // The battery and its percent, travelling as one unit.
                    Item {
                        id: batteryFly

                        width: flat.width + 4 + percentText.implicitWidth
                        height: Math.max(flat.height, percentText.implicitHeight)
                        x: (1 - batterySlot.travel) * batterySlot.spawnX
                        opacity: batterySlot.travel

                        FlatBattery {
                            id: flat

                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            id: percentText

                            anchors.left: flat.right
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: `${BatteryService.percent}%`
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Theme.text
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            TopButtons {
                entries: ControlsService.topButtons
                onRan: root.closed()
                onPanelRequested: panel => root.panelRequested(panel)
                onSettingsRequested: root.settingsRequested()
            }
        }

        // Empty, it is there only while arranging: a place to click and fill.
        Text {
            anchors.centerIn: parent
            visible: root.editing && !ControlsService.hasTop
            text: Tr.t("The top row: click to choose its buttons")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textMuted
        }

        // Outlined and chosen like a block while arranging.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            visible: root.editing
            radius: Theme.radiusMedium + 3
            color: "transparent"
            border.color: parent.chosen ? Theme.accent : Theme.hairline
            border.width: parent.chosen ? 2 : 1
        }

        TapHandler {
            enabled: root.editing
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: ControlsService.selected = parent.chosen ? "" : "top"
        }
    }

    // ── GRID ────────────────────────────────────────────────────────────────

    // Not `board`, the name of the property the blocks are handed: an id and a
    // property with the same name in one scope resolve to the property.
    Item {
        id: surface

        Layout.fillWidth: true
        Layout.fillHeight: true

        // Published for the tray, which lives outside this panel and maps the
        // pointer into these cells.
        Binding {
            target: ControlsService
            property: "board"
            value: surface
        }

        // Right-click on the background toggles arranging. Declared first,
        // beneath everything: blocks take the left button and the right one
        // falls through. Exclusive from the press, or the island's catch-all
        // under the panel takes it; that one answers the panel's margin.
        TapHandler {
            acceptedButtons: Qt.RightButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: ControlsService.edit(!ControlsService.editing)
        }

        // Left-click on the background closes the inspector. A block's own
        // tap is exclusive from the press, so this never fires under one.
        TapHandler {
            enabled: root.editing
            acceptedButtons: Qt.LeftButton
            onTapped: ControlsService.selected = ""
        }

        // The cells, only while arranging.
        Loader {
            anchors.fill: parent
            active: root.editing
            sourceComponent: lattice
        }

        // The drop target, lit on the grid before the drop. Moved
        // imperatively rather than bound, so it appears in place and only
        // animates from cell to cell instead of sliding in from where it was
        // hidden.
        Rectangle {
            id: landing

            readonly property var spot: ControlsService.landing
            property bool showing: false

            visible: root.editing && landing.showing
            radius: Theme.radiusMedium
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
            border.color: Theme.accent
            border.width: 2

            onSpotChanged: {
                if (!landing.spot) {
                    landing.showing = false
                    return
                }
                const box = ControlsService.pixels(landing.spot.size)
                slide.enabled = landing.showing
                landing.x = ControlsService.offsetX(landing.spot.col)
                landing.y = ControlsService.offsetY(landing.spot.row)
                landing.width = box.width
                landing.height = box.height
                slide.enabled = true
                landing.showing = true
            }

            Behavior on x { id: slide; NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easing } }
            Behavior on y { enabled: slide.enabled; NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easing } }
            Behavior on width { enabled: slide.enabled; NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easing } }
            Behavior on height { enabled: slide.enabled; NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easing } }
        }

        // Keyed on block ids rather than rows: a Repeater given a new array
        // rebuilds every delegate, and the rows are a new array after every
        // drop. Ids change only when a block is added or removed, so the snap
        // animates and a playing track or a scrolled list survives a drag.
        Repeater {
            model: ScriptModel {
                values: ControlsService.keys
            }

            Block {
                board: surface
                onPanelRequested: panel => root.panelRequested(panel)
                onSettingsRequested: root.settingsRequested()
                onDismissed: root.closed()
            }
        }

        // The selected block's options, on a card beside it.
        Loader {
            anchors.fill: parent
            z: 5
            active: root.editing && ControlsService.selected !== ""
                && ControlsService.selected !== "top"
            sourceComponent: BlockInspector { board: surface }
        }

        // The top row's, under it at the right.
        Loader {
            anchors.right: parent.right
            y: 0
            z: 5
            active: root.editing && ControlsService.selected === "top"
            sourceComponent: TopRowInspector { limit: surface.height }
        }
    }

    Component {
        id: lattice

        Item {
            Repeater {
                model: ControlsService.columns * ControlsService.rows

                Rectangle {
                    required property int index

                    x: ControlsService.offsetX(index % ControlsService.columns)
                    y: ControlsService.offsetY(Math.floor(index / ControlsService.columns))
                    width: Theme.centreCellWidth
                    height: Theme.centreCellHeight
                    radius: Theme.radiusSmall
                    color: "transparent"
                    border.color: Theme.hairline
                    border.width: 1
                }
            }
        }
    }
}
