// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   D O C K   S E R V I C E                                                │
// │   dock · pinned and running applications                                 │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

pragma Singleton

import QtQml
import QtQuick
import Quickshell

import "../theme"

// The application registry: pinned applications, running windows, and the
// matching of window classes to desktop entries. The dock window is gone;
// the registry stays, for the launcher's favourites, the overview, and
// bringing up a notification's application.
//
// ── MATCHING WINDOWS TO DESKTOP ENTRIES ─────────────────────────────────────
//
// `StartupWMClass` is the intended field but many entries lack it, so the
// entry's file id, its last dotted segment, its `Exec` binary and its name
// are also scored, and the highest claim on a class wins. When several entries
// share a `StartupWMClass` (a browser and its web apps), the one whose id
// matches it wins. Unmatched windows are still shown under their class.
Singleton {
    id: root

    // ── SETTINGS ────────────────────────────────────────────────────────────

    // Kept only to keep the client list live for the overview: the dock
    // window is gone, and this no longer paints anything.
    readonly property bool enabled: SettingsService.dockEnabled

    // ── PINNED ──────────────────────────────────────────────────────────────
    //
    // Kept locally and written to the settings on a debounce. Reading back
    // from the JsonAdapter mid-edit returns a stale value, so consecutive
    // reorders would build on the wrong list.
    property var pinned: SettingsService.dockPinned ?? []

    // How many are pinned: the favourites editor shows an empty state when
    // there are none.
    readonly property int pinnedCount: root.pinned.length

    Connections {
        target: SettingsService

        function onDockPinnedChanged(): void {
            if (saver.running)
                return
            root.pinned = SettingsService.dockPinned ?? []
        }
    }

    readonly property Timer saver: Timer {
        interval: 120
        onTriggered: SettingsService.set("dockPinned", root.pinned)
    }

    function write(next: var): void {
        root.pinned = next
        saver.restart()
    }

    function isPinned(id: string): bool {
        return id !== "" && root.pinned.indexOf(id) >= 0
    }

    function pin(id: string): void {
        if (id === "" || root.isPinned(id))
            return
        root.write(root.pinned.concat([id]))
    }

    function unpin(id: string): void {
        root.write(root.pinned.filter(entry => entry !== id))
    }

    // ── APPLICATION INDEX ───────────────────────────────────────────────────

    readonly property var applications: LauncherService.applications

    function entryOf(id: string): var {
        return root.applications.find(app => app.id === id) ?? null
    }

    // `/usr/bin/foo %U` -> `foo`.
    function binaryOf(exec: string): string {
        const first = (exec ?? "").trim().split(/\s+/)[0] ?? ""
        return first.replace(/"/g, "").split("/").pop()
    }

    // Window class -> best-scoring entry id. Built once from the application
    // list instead of searched on every focus change.
    readonly property var classIndex: {
        const best = ({})
        const claim = (key, id, score) => {
            const normalised = (key ?? "").trim().toLowerCase()
            if (normalised === "")
                return
            const held = best[normalised]
            if (!held || score > held.score)
                best[normalised] = { id: id, score: score }
        }
        for (const app of root.applications) {
            const base = app.id.replace(/\.desktop$/, "")
            const wmclass = app.wmclass ?? ""
            claim(app.name, app.id, 1)
            claim(root.binaryOf(app.exec), app.id, 2)
            // `org.kde.okular` often has the window class `okular`.
            claim(base.split(".").pop(), app.id, 3)
            claim(base, app.id, 4)
            // Bonus when the id matches too: breaks ties between a browser
            // and its web apps.
            claim(wmclass, app.id,
                  wmclass.toLowerCase() === base.toLowerCase() ? 6 : 5)
        }
        return best
    }

    function idFor(windowClass: string): string {
        const key = (windowClass ?? "").trim().toLowerCase()
        const found = key === "" ? null : root.classIndex[key]
        return found ? found.id : ""
    }

    // ── RUNNING ─────────────────────────────────────────────────────────────
    //
    // Keeps `HyprlandService.clients` live while the dock or any note deck
    // needs it (both test for fullscreen windows). Decks are read from the
    // settings, not `DesktopService`, which depends on this service's zone.
    readonly property bool decksExist: {
        const list = SettingsService.desktopWidgets
        const length = list && typeof list.length === "number" ? list.length : 0
        for (let index = 0; index < length; index++) {
            if (list[index] && list[index].edge)
                return true
        }
        return false
    }

    // The workspace strip draws the focused workspace's applications when
    // `workspaceApps` is on, so it needs the list as well.
    readonly property bool stripApps: SettingsService.workspaceApps

    readonly property Binding watching: Binding {
        target: HyprlandService
        property: "watchClients"
        value: root.enabled || root.decksExist || root.stripApps
    }

    onEnabledChanged: {
        if (root.enabled)
            HyprlandService.loadClients()
    }

    onStripAppsChanged: {
        if (root.stripApps)
            HyprlandService.loadClients()
    }

    Component.onCompleted: {
        if (root.enabled || root.stripApps)
            HyprlandService.loadClients()
    }

    // One group per application in first-opened order. Windows without a
    // class are skipped.
    readonly property var groups: {
        const order = []
        const seen = ({})
        for (const client of HyprlandService.clients.concat(HyprlandService.minimizedClients)) {
            const cls = (client.class ?? "").trim()
            if (cls === "")
                continue
            const id = root.idFor(cls)
            const key = id !== "" ? id : `class:${cls.toLowerCase()}`
            if (!seen[key]) {
                seen[key] = { key: key, id: id, cls: cls, windows: [] }
                order.push(seen[key])
            }
            seen[key].windows.push(client)
        }
        return order
    }

    // The application a notification came from, among the open windows: by
    // its desktop entry, else its name. A window class often extends the name
    // (`Brave` and `brave-browser`), so either may start with the other.
    // Null when none matches.
    function groupOfSender(desktopEntry: string, appName: string): var {
        const known = names => names.map(name => (name ?? "").trim().toLowerCase())
            .filter(name => name.length >= 3)
        const told = known([desktopEntry.replace(/\.desktop$/, ""), appName])
        return root.groups.find(group => known([group.id.replace(/\.desktop$/, ""), group.cls])
            .some(own => told.some(name => own.startsWith(name) || name.startsWith(own)))) ?? null
    }

    // True when `showSender` has an application to bring up or start.
    function canShowSender(desktopEntry: string, appName: string): bool {
        return root.groupOfSender(desktopEntry, appName) !== null
            || DesktopEntries.heuristicLookup(desktopEntry || appName) !== null
    }

    // Brings up the application a notification came from: its window (back
    // from minimized if need be), else a new instance when it has a desktop
    // entry. False when there is nothing to bring up.
    function showSender(desktopEntry: string, appName: string): bool {
        const group = root.groupOfSender(desktopEntry, appName)
        if (group) {
            const windows = root.describe(group.id, group.cls, group).windows
            const shown = windows.filter(window => !window.minimized)
            if (shown.length === 0)
                HyprlandService.restoreWindow(windows[0].address)
            else
                HyprlandService.focusWindow(shown[0].address)
            return true
        }
        const entry = DesktopEntries.heuristicLookup(desktopEntry || appName)
        if (!entry)
            return false
        LauncherService.launchDesktop(entry.id)
        return true
    }

    // A fullscreen window on the workspace a screen is showing. Hyprland
    // reports maximised as 1 and fullscreen as 2; only the latter puts the
    // bar in zen — and only on its own screen.
    function coveredOn(name: string): bool {
        const workspace = HyprlandService.activeOn(name)
        return workspace > 0 && HyprlandService.clients.some(
            client => (client.fullscreen ?? 0) >= 2
                && client.workspace && client.workspace.id === workspace)
    }

    // The screens under a fullscreen window, as one padded string. A plain
    // value rather than a list, so the bar's zen state is worked out again
    // when the answer changes and not every time a window changes its title:
    // the client list is read here, once, instead of by a board's every
    // binding.
    readonly property string coveredScreens: {
        let out = " "
        for (const screen of Quickshell.screens)
            if (root.coveredOn(screen.name))
                out += screen.name + " "
        return out
    }

    // ── DESCRIBE ────────────────────────────────────────────────────────────
    //
    // One row for a running application, used by `showSender` when a
    // notification's sender action needs it. A pinned entry whose desktop
    // file is gone keeps its slot under its id, so it can still be unpinned.
    //
    function describe(id: string, cls: string, group: var): var {
        const entry = id !== "" ? root.entryOf(id) : null
        const windows = group ? group.windows : []
        return {
            key: id !== "" ? id : `class:${cls.toLowerCase()}`,
            id: id,
            name: entry ? entry.name : (cls !== "" ? cls : id.replace(/\.desktop$/, "")),
            icon: entry ? entry.icon : cls.toLowerCase(),
            pinned: root.isPinned(id),
            // Listed individually for the context menu.
            windows: windows.map(client => ({
                address: client.address,
                title: client.title || client.class,
                workspace: client.workspace ? client.workspace.id : 0,
                // The focused window, so a repeat click can cycle to the next
                // one. Uses the focused address rather than `focusHistoryID`,
                // which is stale after focusing an empty workspace.
                front: client.address === HyprlandService.focusedAddress,
                minimized: client.workspace?.name === HyprlandService.minimizedWorkspace
            })),
            running: windows.length > 0,
            // A minimized window can keep the focus when it left an empty
            // workspace behind; it is not in front for that.
            active: windows.some(client => client.address === HyprlandService.focusedAddress
                && client.workspace?.name !== HyprlandService.minimizedWorkspace)
        }
    }
}
