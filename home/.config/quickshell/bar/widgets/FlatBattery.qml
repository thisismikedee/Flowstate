// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   F L A T   B A T T E R Y                                                │
// │   the control centre's top-row battery · drawn, flat 2D, on its side    │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Shapes

import "../../theme"
import "../../services"

// The top-row battery, drawn instead of an icon glyph: a horizontal
// battery lying on its side — a rounded rectangle with a charge fill —
// flat and 2D, solid colours only. No gradients, no translucency, no
// glossy highlight, no glass sheen, no soft rim. The body is a solid dark
// gray; the fill is a solid slab of the service's tint covering the left
// part by charge level, its right edge a straight line; a small dark-gray
// terminal nub sits on the right end. A bold solid white bolt sits over
// the fill while charging. It reads BatteryService only.
Item {
    id: root

    // The body's size: a little smaller than the glass one was, roughly
    // the text height tall. The corners are moderately rounded — about a
    // third of the height — a rounded rect, not a full pill.
    readonly property int bodyWidth: 28
    readonly property int bodyHeight: 16
    readonly property int bodyRadius: 5
    readonly property int nubWidth: 3
    readonly property int nubHeight: 7
    // The empty part's solid dark gray, and the nub's: the theme's dim
    // indicator gray, which reads on the control centre's dark ground.
    readonly property color empty: Theme.indicatorDim

    implicitWidth: root.bodyWidth + root.nubWidth
    implicitHeight: root.bodyHeight

    readonly property real level: BatteryService.available ? BatteryService.percent / 100 : 0
    readonly property color tint: BatteryService.tint
    readonly property bool dim: !BatteryService.available

    // The body: solid dark gray, clipped so the fill inside it follows
    // the rounded left corners and stops at a straight right edge.
    Rectangle {
        id: body

        width: root.bodyWidth
        height: root.bodyHeight
        radius: root.bodyRadius
        color: root.empty
        clip: true
        opacity: root.dim ? 0.45 : 1

        // The charge fill: a solid slab of the service's tint, its width
        // following the level. A plain rectangle — the body's clip rounds
        // its left edge and keeps its right edge straight.
        Rectangle {
            width: parent.width * root.level
            height: parent.height
            color: root.tint
        }
    }

    // The terminal nub on the right end, the same solid dark gray as the
    // empty part.
    Rectangle {
        x: root.bodyWidth - 1
        y: (root.bodyHeight - root.nubHeight) / 2
        width: root.nubWidth
        height: root.nubHeight
        radius: 2
        color: root.empty
        opacity: root.dim ? 0.45 : 1
    }

    // A bold solid white bolt while charging, centred on the body over
    // the fill, overlapping the fill's edge like the reference. A static
    // bolt, not a pulse: at this size the bolt alone says charging, and
    // a pulse would read as a flicker.
    Shape {
        visible: BatteryService.charging
        anchors.centerIn: body
        width: 10
        height: 14
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "#ffffff"
            strokeWidth: -1
            startX: 6
            startY: 0
            PathLine { x: 1; y: 7 }
            PathLine { x: 4; y: 7 }
            PathLine { x: 3; y: 14 }
            PathLine { x: 9; y: 6 }
            PathLine { x: 6; y: 6 }
            PathLine { x: 6; y: 0 }
        }
    }
}
