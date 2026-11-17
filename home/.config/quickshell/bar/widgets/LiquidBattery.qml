// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   L I Q U I D   B A T T E R Y                                            │
// │   the control centre's top-row battery · drawn, glass, on its side      │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Shapes

import "../../theme"
import "../../services"

// The top-row battery, drawn instead of an icon glyph: a horizontal
// battery lying on its side — a rounded body with a small terminal nub
// on the right, a charge fill inside — in the shell's Liquid Glass
// idiom. The body is a full pill (its radius is half its height), the
// same pill nature as the island itself: a translucent glass shell,
// lighter at the top, with a thin soft rim, and the fill carries the
// same glassy gradient in the service's tint. A drawn bolt sits over
// the fill while charging. It reads BatteryService only.
Item {
    id: root

    // The body's size: a soft pill, roughly the text height tall.
    readonly property int bodyWidth: 32
    readonly property int bodyHeight: 18
    readonly property int nubWidth: 4
    readonly property int nubHeight: 8
    // The wall of the glass shell: the fill sits this far inside it.
    readonly property int wall: 2

    implicitWidth: root.bodyWidth + root.nubWidth
    implicitHeight: root.bodyHeight

    readonly property real level: BatteryService.available ? BatteryService.percent / 100 : 0
    readonly property color tint: BatteryService.tint
    readonly property bool dim: !BatteryService.available

    // The glass shell: translucent, lighter at the top so it reads as
    // glass, with a thin soft rim.
    Rectangle {
        id: body

        width: root.bodyWidth
        height: root.bodyHeight
        radius: height / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.28) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.10) }
        }
        border.color: Qt.rgba(1, 1, 1, 0.35)
        border.width: 1
        opacity: root.dim ? 0.45 : 1

        // The charge fill: a pill inside the shell, its width following
        // the level, in the service's tint with the same glassy gradient
        // (lighter at the top). The radius is clamped to half the width
        // when the level is very low, so it stays a capsule.
        Rectangle {
            x: root.wall
            y: root.wall
            width: Math.max(0, (parent.width - 2 * root.wall) * root.level)
            height: parent.height - 2 * root.wall
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(root.tint, 1.35) }
                GradientStop { position: 1.0; color: root.tint }
            }
        }
    }

    // The terminal nub on the right end, the same glass as the body.
    Rectangle {
        x: root.bodyWidth - 1
        y: (root.bodyHeight - root.nubHeight) / 2
        width: root.nubWidth
        height: root.nubHeight
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.22)
        border.color: Qt.rgba(1, 1, 1, 0.30)
        border.width: 1
        opacity: root.dim ? 0.45 : 1
    }

    // A drawn bolt while charging, centred on the body over the fill.
    // A static bolt, not a pulse: at this size the bolt alone says
    // charging, and a pulse would read as a flicker.
    Shape {
        visible: BatteryService.charging
        anchors.centerIn: body
        width: 8
        height: 12
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: Qt.rgba(1, 1, 1, 0.95)
            strokeWidth: -1
            startX: 5
            startY: 0
            PathLine { x: 1; y: 6.5 }
            PathLine { x: 3.5; y: 6.5 }
            PathLine { x: 2.5; y: 12 }
            PathLine { x: 7; y: 5 }
            PathLine { x: 4.5; y: 5 }
            PathLine { x: 5; y: 0 }
        }
    }
}
