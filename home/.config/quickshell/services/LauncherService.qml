// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   L A U N C H E R   S E R V I C E                                        │
// │   application index · search and activation                              │
// │                                                                          │
// │   github.com/thisismikedee/Flowstate                                     │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import "../theme"

// Application index and launcher query logic.
//
// Two modes, nothing else: plain text searches applications, and `=` in
// front works something out. Modes are explicit so `100` is never misread
// as a sum.
QtObject {
    id: root

    readonly property int maxResults: SettingsService.launcherResults

    // The prefix-less mode must be last. Sigils come from the settings
    // (`SettingsService.launcherPrefixDefaults`).
    readonly property var modes: [
        { id: "calculate", prefix: SettingsService.launcherPrefix("calculate"),
          label: Tr.t("Calculate"), icon: "󰃬",
          hint: Tr.t("Work something out"), empty: Tr.t("An expression — 12 * 34, (5 + 5) / 2") },
        { id: "apps",      prefix: "",  label: Tr.t("Apps"), icon: "󰀻",
          hint: Tr.t("Search applications"),
          empty: Tr.t("No application matches.") }
    ]

    function modeFor(query: string): var {
        const raw = query ?? ""
        for (const mode of root.modes) {
            if (mode.prefix !== "" && raw.startsWith(mode.prefix))
                return mode
        }
        return root.modes[root.modes.length - 1]
    }

    function termFor(query: string): string {
        return (query ?? "").slice(root.modeFor(query).prefix.length).trim()
    }

    // ── QUERY AND SIZE ──────────────────────────────────────────────────────
    //
    // The query lives here, not in the panel, because with `launcherFits` the
    // panel height depends on the results and the island must know its size
    // before the panel exists. Cleared when the panel closes.
    property string query: ""

    readonly property var results: root.search(root.query)

    // Panel metrics, shared with the layout so the height math stays in sync.
    readonly property int fieldHeight: 34
    readonly property int rowHeight: 48
    readonly property int rowSpacing: 2
    readonly property int gap: 12

    // Field, divider, and the gap on either side of the divider.
    readonly property int chromeHeight: root.fieldHeight + 2 * root.gap + 1

    // At least one row, for the "no results" line.
    readonly property int rows: Math.max(1, Math.min(root.results.length, root.maxResults))

    function listHeight(rows: int): int {
        return rows * root.rowHeight + (rows - 1) * root.rowSpacing
    }

    function heightFor(rows: int): int {
        return root.chromeHeight + root.listHeight(rows) + 2 * Theme.panelPadding
    }

    readonly property int panelWidth: 560

    // Fixed height with a scrolling list, or (`launcherFits`) sized to the
    // results up to `maxResults` rows.
    readonly property int panelHeight:
        SettingsService.launcherFits ? root.heightFor(root.rows) : 520

    // Whitelist: the expression is passed to a JavaScript evaluator.
    readonly property var arithmetic: /^[0-9+\-*/(). %]+$/

    property var applications: []

    // ── LAUNCH HISTORY ──────────────────────────────────────────────────────
    //
    // Results are ranked by a launch count with exponential decay (frecency),
    // stored in the state directory.
    readonly property string order: SettingsService.launcherOrder

    readonly property real halfLife: 30 * 24 * 3600 * 1000

    // Mirrors the adapter; reading a JsonAdapter back in the same turn as a
    // write returns the old value.
    property var launches: ({})

    readonly property FileView historyFile: FileView {
        path: `${SettingsService.stateDirectory}/launcher-history.json`
        watchChanges: true

        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoaded: root.launches = history.launches ?? ({})
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter()
        }

        JsonAdapter {
            id: history

            // Desktop id -> { count, last }. Decay is applied on read.
            property var launches: ({})
        }
    }

    function scoreOf(id: string): real {
        const row = root.launches[id]
        if (!row || !row.count)
            return 0
        const age = Date.now() - (row.last ?? 0)
        return row.count * Math.pow(0.5, age / root.halfLife)
    }

    function record(id: string): void {
        if (!id)
            return
        const next = Object.assign({}, root.launches)
        next[id] = { count: root.scoreOf(id) + 1, last: Date.now() }
        root.launches = next
        history.launches = next
    }

    // ── FAVOURITES ──────────────────────────────────────────────────────────
    //
    // The dock's pinned apps, read from the settings rather than `DockService`
    // (which depends on this service). They get a bonus of one launch.
    readonly property var favourites: SettingsService.dockPinned ?? []

    function weightOf(app: var): real {
        return root.scoreOf(app.id)
            + (root.favourites.indexOf(app.id) >= 0 ? 1 : 0)
    }

    readonly property Process applicationsProcess: Process {
        command: [Quickshell.shellPath("scripts/applications.py")]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || text.trim() === "")
                    return
                try {
                    root.applications = JSON.parse(text)
                } catch (error) {
                    console.warn("Cannot parse the application list:", error)
                }
            }
        }
    }

    // Launches use execDetached, not Process: a Process child dies with a
    // config reload, and gtk-launch run that way exits 0 without launching.

    function refresh(): void {
        root.applicationsProcess.running = true
    }

    function search(query: string): var {
        const mode = root.modeFor(query)
        const raw = root.termFor(query)
        const term = raw.toLowerCase()

        if (mode.id === "calculate")
            return root.calculate(raw)

        // A sum typed without the calculator's prefix, first. It needs a
        // digit and an operator, so a bare number or a name is not taken for
        // one.
        const sum = /\d/.test(raw) && /[+\-*/%]/.test(raw)
            ? root.calculate(raw) : []
        // Every match: the panel caps its visible height at `maxResults`
        // rows and the rest scrolls, as the doors' list does.
        const applications = sum.concat(root.rank(term))
        return applications.concat(root.fallbacks(raw))
    }

    // ── FALLBACK ROWS ───────────────────────────────────────────────────────
    //
    // Under the applications: search the web, or run the text as a command.
    // Each row carries its `argv`, not a function, which a model would drop
    // on the way to a click.
    readonly property string defaultSearchUrl: "https://www.google.com/search?q="

    function fallbacks(text: string): var {
        const query = text.trim()
        if (query === "")
            return []
        const searchUrl = SettingsService.launcherSearchUrl || root.defaultSearchUrl
        const searchHost = (searchUrl.match(/^https?:\/\/([^\/?#]+)/) ?? [])[1] ?? ""
        const rows = []
        rows.push({ kind: "command", id: "web", icon: "󰜏",
                    name: Tr.t("Search the web for “%1”").arg(query),
                    subtitle: searchHost || Tr.t("Web search"),
                    argv: ["xdg-open", searchUrl + encodeURIComponent(query)] })
        rows.push({ kind: "command", id: "run", icon: "󰆍",
                    name: Tr.t("Run %1").arg(query), subtitle: Tr.t("As a command, in the background"),
                    argv: ["sh", "-c", query] })
        return rows
    }

    // All applications matching `term`, sorted by:
    //
    //   1. name starts with the term (applies in every order)
    //   2. weight: decayed launches plus the favourite bonus
    //   3. dock order, between two favourites of equal weight
    //   4. name
    //
    // With `order` set to alphabetical only 1 and 4 apply.
    function rank(term: string): var {
        const found = []
        for (const app of root.applications) {
            if (term !== "" && !app.name.toLowerCase().includes(term)
                    && !app.keywords.includes(term))
                continue
            found.push(app)
        }

        const byUse = root.order !== "alphabetical"
        found.sort((a, b) => {
            if (term !== "") {
                const leadA = a.name.toLowerCase().startsWith(term) ? 0 : 1
                const leadB = b.name.toLowerCase().startsWith(term) ? 0 : 1
                if (leadA !== leadB)
                    return leadA - leadB
            }
            if (byUse) {
                const weight = root.weightOf(b) - root.weightOf(a)
                if (Math.abs(weight) > 0.0001)
                    return weight
                const keptA = root.favourites.indexOf(a.id)
                const keptB = root.favourites.indexOf(b.id)
                if (keptA >= 0 && keptB >= 0 && keptA !== keptB)
                    return keptA - keptB
            }
            // Accents and case aside, so Á files under A as the index does.
            return a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
        })
        return found
    }

    function calculate(expression: string): var {
        if (expression === "" || !root.arithmetic.test(expression))
            return []
        const value = root.evaluate(expression)
        if (value === null)
            return []
        return [{
            kind: "calculation", id: "", icon: "󰃬",
            name: `${value}`, subtitle: Tr.t("%1  ·  Enter copies it").arg(expression)
        }]
    }

    function evaluate(expression: string): var {
        try {
            const value = Function(`"use strict"; return (${expression})`)()
            return Number.isFinite(value) ? value : null
        } catch (error) {
            return null
        }
    }

    function activate(entry: var): void {
        if (!entry)
            return
        if (entry.kind === "app") {
            // Recorded here, not in `launchDesktop`, so dock launches do not
            // count towards the ranking.
            root.record(entry.id)
            root.launchDesktop(entry.id)
        }
        else if (entry.kind === "calculation")
            root.copy(entry.name)
        else if (entry.kind === "command")
            Quickshell.execDetached(entry.argv)
    }

    function copy(text: string): void {
        Quickshell.execDetached(["wl-copy", "--", text])
    }

    function launchDesktop(desktopId: string): void {
        if (!desktopId)
            return
        Quickshell.execDetached(["gtk-launch", desktopId])
    }
}
