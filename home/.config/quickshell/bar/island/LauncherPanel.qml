// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   L A U N C H E R   P A N E L                                            │
// │   launcher · applications and the calculator                             │
// │                                                                          │
// │   github.com/thisismikedee/Flowstate                                     │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import "../../theme"
import "../../services"
import "../../components"

// Application launcher. Plain text searches applications; `=` in front
// works something out and Enter copies the answer.
ColumnLayout {
    id: root

    // The query lives in the service: with `launcherFits` on, the panel's
    // height depends on it, and the island needs that before the panel exists.
    readonly property var results: LauncherService.results
    readonly property var mode: LauncherService.modeFor(LauncherService.query)

    signal closed()

    spacing: LauncherService.gap

    // Created on open, so this is where the field takes focus; otherwise the
    // window is focusable but nothing inside receives keys.
    //
    // The application index is refreshed here too. The index is otherwise
    // built once, when `LauncherService` is first touched, and would miss
    // anything installed since. Refreshing on open is cheaper than watching
    // the XDG directories; the new list lands about 50 ms later.
    Component.onCompleted: {
        searchField.forceActiveFocus()
        LauncherService.refresh()
    }

    // Cleared on the way out, not on the way in: the island is sized from the
    // query a frame before this panel is built, so clearing it on open would
    // size the island for the last search and then resize it.
    Component.onDestruction: {
        LauncherService.query = ""
    }

    // The list wraps around at both ends.
    function move(delta: int): void {
        const count = root.results.length
        if (count === 0)
            return
        resultList.currentIndex = (resultList.currentIndex + delta + count) % count
        resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
    }

    function kindColour(kind: string): color {
        switch (kind) {
        case "calculation": return Theme.green
        default: return Theme.accent
        }
    }

    // Everything the service runs, and the launcher closes.
    function run(entry: var): void {
        if (!entry)
            return
        LauncherService.activate(entry)
        root.closed()
    }

    // ── FIELD ───────────────────────────────────────────────────────────────
    //
    // Text on the panel's own black with a rule underneath, not a bordered
    // box: the field always has focus, so a focus ring would never turn off.
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: LauncherService.fieldHeight
        spacing: LauncherService.gap

        // The current mode's glyph rather than a magnifier.
        Text {
            text: root.mode.icon
            font.family: Theme.fontMono
            font.pixelSize: 17
            color: Theme.accent

            Behavior on text { enabled: false }
        }

        TextInput {
            id: searchField

            Layout.fillWidth: true
            text: LauncherService.query
            font.family: Theme.fontFamily
            font.pixelSize: 16
            color: Theme.text
            clip: true
            selectByMouse: true
            selectionColor: Theme.accent
            selectedTextColor: Theme.accentText

            onTextEdited: LauncherService.query = text
            Keys.onReturnPressed: root.run(root.results[resultList.currentIndex])
            Keys.onEnterPressed: root.run(root.results[resultList.currentIndex])
            Keys.onUpPressed: root.move(-1)
            Keys.onDownPressed: root.move(1)
            // Escape is handled by the island for every panel.

            // The query can be set from outside (a key that opens the launcher
            // in a mode). Typing breaks the `text` binding, so it is resynced
            // here, or the field would show a stale query.
            Connections {
                target: LauncherService

                function onQueryChanged(): void {
                    if (searchField.text !== LauncherService.query)
                        searchField.text = LauncherService.query
                }
            }

            // Only while the field is empty; it would draw over a typed sigil.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Search…")
                visible: searchField.text === ""
                color: Theme.textMuted
                font: searchField.font
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.borderIn(QsWindow.window)
    }

    // Explicit empty state.
    Text {
        Layout.fillWidth: true
        visible: root.results.length === 0 && LauncherService.query !== ""
        text: root.mode.empty
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
    }

    // ── RESULTS ─────────────────────────────────────────────────────────────
    //
    // One list of rows. Something is always selected, so Enter always runs
    // a result.
    ListView {
        id: resultList

        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: LauncherService.rowSpacing
        model: ScriptModel {
            values: root.results

            // Back to the top once the rows have landed, not when the list
            // changes: a row inserted above the selection would shift it.
            onValuesChanged: {
                resultList.currentIndex = 0
                resultList.positionViewAtBeginning()
            }
        }
        boundsBehavior: Flickable.StopAtBounds
        // The delegate paints the selection itself; no separate highlight.
        currentIndex: 0

        delegate: Rectangle {
            id: row

            required property var modelData
            required property int index

            // Pointer and keyboard share one selection, so Enter always runs
            // what is lit.
            readonly property bool selected: ListView.view.currentIndex === row.index

            width: ListView.view.width
            height: LauncherService.rowHeight
            radius: Theme.radiusSmall
            color: row.selected ? Theme.surfaceHoverIn(QsWindow.window) : "transparent"

            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 12
                spacing: 12

                // Applications get their themed icon; other kinds get a glyph
                // in a tinted disc.
                Item {
                    id: badge

                    // Named rather than reached through `parent`, which inside
                    // this binding is the row.
                    readonly property bool isApp: row.modelData.kind === "app"
                    readonly property string iconSource: badge.isApp && row.modelData.icon
                        ? Theme.appIcon(row.modelData.icon) : ""

                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        id: appIcon
                        anchors.fill: parent
                        source: badge.iconSource
                        visible: badge.iconSource !== "" && status === Image.Ready
                        sourceSize.width: 52
                        sourceSize.height: 52
                        asynchronous: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: !appIcon.visible
                        radius: width / 2
                        color: Theme.surfaceHoverIn(QsWindow.window)

                        Text {
                            anchors.centerIn: parent
                            text: badge.isApp ? "󰀻" : row.modelData.icon
                            font.family: Theme.fontMono
                            font.pixelSize: 14
                            color: root.kindColour(row.modelData.kind)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        elide: Text.ElideRight
                        font.family: row.modelData.kind === "calculation"
                            ? Theme.fontMono : Theme.fontFamily
                        font.pixelSize: Theme.fontSizeRegular
                        font.weight: row.modelData.kind === "calculation"
                            ? Font.DemiBold : Font.Normal
                        color: Theme.text
                    }

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.subtitle
                        visible: row.modelData.subtitle !== ""
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLabel
                        color: Theme.textMuted
                    }
                }

                // Marks apps kept on the dock, which is why they rank near the
                // top of an empty query.
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    visible: row.modelData.kind === "app"
                        && LauncherService.favourites.indexOf(row.modelData.id) >= 0
                    text: "󱂩"
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    color: Theme.textMuted
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // On movement, not hover: a row appearing under a resting
                // pointer would otherwise steal the selection on open.
                onPositionChanged: row.ListView.view.currentIndex = row.index
                onClicked: root.run(row.modelData)
            }
        }
    }
}
