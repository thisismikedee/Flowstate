// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   T I M E   T R A V E L L E R                                            │
// │   the island's one time · travels between rest and glance               │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../theme"
import "../../services"

// The island's time, as one element. At rest it is the small time centred
// in the pill; in the glance it is the large time at the far end, with the
// day and the date under it. It is never hidden and re-shown: a single
// `morph` (0 at rest, 1 in the glance) drives its size and its place, so it
// glides and grows with the island instead of swapping.
//
// One animated value only. Every size and position below is a pure function
// of `morph` (and the island's own size, which morphs on the same clock),
// so nothing fights: the island's width and height already animate on
// `Theme.durationMorph`, and this rides them.
Item {
    id: root

    // True while the island shows the glance (the pointer resting on it).
    property bool summary: false
    // False while the island shows an OSD or a notification in place of the
    // clock. A panel no longer hides it: the time stays put.
    property bool shown: true
    // The island's notch offset, so the rest position is anchored to the
    // pill band at the top rather than the island's current height.
    property real notchPad: 0
    // True while the island is a paper note: the ink goes dark so it reads
    // on the light paper.
    property bool paper: false

    property real morph: root.summary ? 1 : 0

    Behavior on morph {
        NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing }
    }

    SystemClock {
        id: clock
        precision: SettingsService.clockShowsSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    readonly property var locale: Qt.locale(SettingsService.language)

    readonly property string format: SettingsService.clockShowsSeconds
        ? SettingsService.clockFormat.replace("mm", "mm:ss")
        : SettingsService.clockFormat

    // The day and date lines only where the glance shows them: beside the
    // five days they would repeat what the days already say.
    readonly property bool dated: ModuleService.glanceFace !== "clock"

    // The rest's offset when something overflowed past the sides.
    readonly property int spare: ModuleService.overflow > 0 ? ModuleService.overflowWidth : 0

    // The ink: the shell's text, or the paper's dark ink on a note.
    readonly property color ink: root.paper ? Theme.paperInk : Theme.text
    readonly property color inkMuted: root.paper ? Theme.paperInkMuted : Theme.textMuted

    // The face's geometry in the glance (IslandSummary's slot), in island
    // coordinates: the slot's centre is where the large time hangs.
    readonly property int margin: ModuleService.glanceMargin
    readonly property int slotCenterY: root.margin + ModuleService.glanceStatusHeight
        + (ModuleService.glanceFaceHeight - 2 * root.margin) / 2

    // The hour's size, growing from the rest's type to the glance's.
    readonly property real hourSize: Theme.fontSizeRegular + (62 - Theme.fontSizeRegular) * root.morph

    // The width and height at each end, from the type itself so they track
    // the growing hour; the middle is the straight line between them.
    readonly property real restW: hour.implicitWidth
        + (SettingsService.clockShowsDate ? 8 + restDate.implicitWidth : 0)
    readonly property real sumW: Math.max(hour.implicitWidth,
        root.dated ? weekday.implicitWidth : 0,
        root.dated ? date.implicitWidth : 0)
    readonly property real restH: hour.implicitHeight
    readonly property real sumH: hour.implicitHeight
        + (root.dated ? weekday.implicitHeight + date.implicitHeight - 12 : 0)

    width: root.restW + (root.sumW - root.restW) * root.morph
    height: root.restH + (root.sumH - root.restH) * root.morph

    // Centred on the rest's middle (less the overflow offset), right-aligned
    // to the glance's far edge. Both ends are functions of the width, so the
    // glide follows the growth.
    readonly property real restX: parent.width / 2 - root.spare / 2 - width / 2
    readonly property real sumX: parent.width - root.margin - 4 - width
    x: root.restX + (root.sumX - root.restX) * root.morph

    // Centred in the pill band at the top at rest — anchored to the pill's
    // own height, not the island's current height, so the time stays put
    // while a panel grows below it. Hung from the slot's centre in the
    // glance.
    readonly property real restY: (Theme.capsuleHeight + root.notchPad - height) / 2
    readonly property real sumY: root.slotCenterY - height / 2
    y: root.restY + (root.sumY - root.restY) * root.morph

    opacity: root.shown ? 1 : 0

    Behavior on opacity {
        NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easing }
    }

    // The hour itself: the constant. It grows from the rest's DemiBold to
    // the glance's Black, and slides from the near edge to the far edge so
    // the day and date can sit under it.
    Text {
        id: hour

        x: (root.width - implicitWidth) * root.morph
        y: 0
        text: Tr.date(clock.date, root.format)
        font.family: Theme.fontFamily
        font.pixelSize: root.hourSize
        font.weight: root.morph > 0.5 ? Font.Black : Font.DemiBold
        color: root.ink
    }

    Text {
        id: weekday

        visible: root.dated
        x: root.width - implicitWidth
        y: hour.implicitHeight - 6
        text: root.locale.toString(clock.date, "dddd").toUpperCase()
        font.family: Theme.fontFamily
        font.pixelSize: 20
        font.weight: Font.Black
        color: root.ink
        opacity: root.morph
    }

    Text {
        id: date

        visible: root.dated
        x: root.width - implicitWidth
        y: weekday.y + weekday.implicitHeight - 6
        text: root.locale.toString(clock.date, "d MMMM").toUpperCase()
        font.family: Theme.fontFamily
        font.pixelSize: 15
        font.weight: Font.Black
        color: root.inkMuted
        opacity: root.morph
    }

    // The rest's small date, beside the hour while the island is at rest.
    Text {
        id: restDate

        visible: SettingsService.clockShowsDate
        x: hour.x + hour.implicitWidth + 8
        y: (hour.implicitHeight - implicitHeight) / 2
        text: Tr.date(clock.date, "ddd d MMM")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: root.inkMuted
        opacity: SettingsService.clockShowsDate ? 1 - root.morph : 0
    }
}
