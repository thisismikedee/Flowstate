// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   L O C K   S E R V I C E                                                │
// │   session lock state · background capture and authentication             │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

import "../theme"

// Locks the session through ext-session-lock instead of an external locker,
// so the desktop can stay on screen behind the lock, blurred.
//
// The screenshot is a grim process rather than a ScreencopyView because it
// has to finish before the lock surface is mapped. It goes to the runtime
// directory (tmpfs, user-only) and is deleted on unlock.
//
// The password is handed straight to PAM's `respond` and never stored past
// the field it is typed in, which every screen shares and which empties on
// sending, on rest and on unlock.
Singleton {
    id: root

    property bool locked: false

    // `locked` is the request; this is the compositor confirming the screen
    // is covered.
    property bool secure: false

    property bool authenticating: false
    property string message: ""
    property bool failed: false

    // From the moment the lock is answered until the surface has let go of
    // the desktop; `locked` falls after it.
    property bool leaving: false

    // Two stages, shared by every screen: at rest the clock alone, awake the
    // account, the field and the power buttons. A key or a click wakes it,
    // Escape or a while untouched puts it back.
    property bool awake: false

    // What is typed, one field for every screen: each surface shows it and
    // writes to it, so the dots are the same wherever the keyboard is.
    property string typed: ""

    // How long an awake screen waits untouched before going back to its
    // clock.
    readonly property int awakeFor: 30000

    function rouse(): void {
        if (!root.locked || root.leaving)
            return
        root.awake = true
        root.drowse.restart()
    }

    // Surfaces clear their field when this falls.
    function rest(): void {
        root.drowse.stop()
        root.awake = false
        root.typed = ""
        root.failed = false
        root.message = ""
    }

    readonly property Timer drowse: Timer {
        interval: root.awakeFor
        // A password being checked is not a screen left alone.
        onTriggered: root.authenticating ? root.drowse.restart() : root.rest()
    }

    readonly property string shotDirectory:
        `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/quickshell`

    // One picture per screen, named by its output, so each surface shows
    // its own screen rather than all of them squeezed into one.
    function shotPath(output: string): string {
        return `${root.shotDirectory}/lock-${output}.jpg`
    }

    // Bumped per capture so the Image source changes and Qt does not serve
    // the previous lock's cached frame.
    property int shotSerial: 0
    property bool shotReady: false

    // Empty when that screen's capture failed, and the surface stays black.
    function shotSource(output: string): string {
        if (root.wallpaperSource !== "")
            return root.wallpaperSource
        return root.shotReady && output
            ? `file://${root.shotPath(output)}?v=${root.shotSerial}` : ""
    }

    // With `lockMusicGround: wallpaper`, the wallpaper stands behind the lock
    // in place of the screenshot, latched when it locks. No screenshot is
    // taken, and a wallpaper that does not load leaves the island's black:
    // nothing that was open ever shows.
    property string wallpaperSource: ""

    signal unlocked()

    // ── LOCKING ─────────────────────────────────────────────────────────────

    // False while a panel is still on screen and would end up in the
    // screenshot. Bound in `shell.qml`, which can see the bar.
    property bool shellQuiet: true

    property bool pendingCapture: false

    function lock(): void {
        if (root.locked)
            return
        root.message = ""
        root.failed = false
        root.leaving = false
        root.rest()
        root.shotReady = false
        root.wallpaperSource = ""
        if (SettingsService.lockMusicGround === "wallpaper") {
            const wallpaper = WallpaperService.currentWallpaper
            root.wallpaperSource = wallpaper !== "" ? DesktopService.urlOf(wallpaper) : ""
            root.engage()
            return
        }
        // Capture first, surface second — and only once the island has
        // closed, or the screenshot shows the panel the lock came from.
        root.pendingCapture = true
        root.attemptCapture()
    }

    // The screen is covered and the password is asked for.
    function engage(): void {
        root.locked = true
        root.begin()
    }

    function attemptCapture(): void {
        if (!root.pendingCapture)
            return
        if (!root.shellQuiet) {
            root.settleFrame.stop()
            root.quietGiveUp.restart()
            return
        }
        root.settleFrame.restart()
    }

    onShellQuietChanged: root.attemptCapture()

    // grim reads the compositor, not this scene graph, and there is no signal
    // for "the frame is on screen": two frames at 60 Hz.
    readonly property Timer settleFrame: Timer {
        interval: 32
        onTriggered: root.beginCapture()
    }

    // Lock anyway if the shell never settles: an untidy screenshot is better
    // than an unlocked machine.
    readonly property Timer quietGiveUp: Timer {
        interval: 900
        onTriggered: {
            console.warn("The shell did not settle; locking with whatever is on screen.")
            root.beginCapture()
        }
    }

    function beginCapture(): void {
        if (!root.pendingCapture)
            return
        root.pendingCapture = false
        root.settleFrame.stop()
        root.quietGiveUp.stop()
        root.capture.command = ["sh", "-c", root.captureScript()]
        root.capture.running = true
    }

    // Every screen at once, each into its own file, and the lock waits for
    // the slowest.
    function captureScript(): string {
        const shots = Quickshell.screens
            .filter(screen => /^[A-Za-z0-9_.-]+$/.test(screen.name))
            .map(screen => `timeout 2 grim -t jpeg -q 90 -o '${screen.name}' '${root.shotPath(screen.name)}' &`)
        return `mkdir -p '${root.shotDirectory}' && rm -f '${root.shotDirectory}'/lock-*.jpg; ${shots.join(" ")} wait`
    }

    // grim hangs instead of failing when the output is already powered off,
    // and the lock only goes up in `onExited`, hence the timeout. JPEG, since
    // the picture is shown blurred and PNG takes seconds over a painting on a
    // large or doubled screen.
    readonly property Process capture: Process {
        // Lock whether or not the screenshot worked.
        onExited: (code, status) => {
            root.shotSerial += 1
            root.shotReady = code === 0
            root.engage()
        }
    }

    function forget(): void {
        root.typed = ""
        root.shotReady = false
        root.wallpaperSource = ""
        root.eraser.running = true
    }

    readonly property Process eraser: Process {
        command: ["sh", "-c", `rm -f '${root.shotDirectory}'/lock-*.jpg`]
    }

    // ── AUTHENTICATING ──────────────────────────────────────────────────────

    // A PAM conversation ends after a refusal, so every attempt starts a new
    // one.
    function begin(): void {
        if (pam.active)
            pam.abort()
        root.authenticating = false
        pam.start()
    }

    function submit(password: string): void {
        if (root.authenticating || root.leaving)
            return
        // Enter on an empty field asks for the camera instead.
        if (password === "") {
            root.scan()
            return
        }
        root.failed = false
        root.message = ""

        // PAM has normally asked by now. If not, restart it and let the user
        // retry rather than keep the password around until it does.
        if (!pam.responseRequired) {
            root.begin()
            root.message = Tr.t("Not ready — press Enter again")
            return
        }

        root.authenticating = true
        pam.respond(password)
    }

    readonly property PamContext pam: PamContext {
        // The same stack hyprlock's PAM file includes.
        config: "login"

        onCompleted: result => {
            root.authenticating = false
            if (result === PamResult.Success) {
                root.release()
                return
            }
            root.failed = true
            root.message = result === PamResult.MaxTries
                ? Tr.t("Too many attempts")
                : Tr.t("Wrong password")
            root.begin()
        }

        onError: error => {
            root.authenticating = false
            root.failed = true
            root.message = Tr.t("Authentication is unavailable")
            console.warn("PAM error while unlocking:", error)
        }
    }

    // ── KEYBOARD ────────────────────────────────────────────────────────────
    //
    // Caps Lock and the layout, from the main keyboard, read every second
    // while locked: a password typed on the wrong layout or with Caps Lock on
    // is the usual reason for a refusal. Hyprland sends no event for Caps
    // Lock, so it is asked.
    property bool capsLock: false
    property string keymap: ""
    // How many layouts the keyboard switches between; the one in use is
    // worth saying only when there is a choice.
    property int layouts: 1

    readonly property Process keyboardReader: Process {
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const keyboards = JSON.parse(text).keyboards ?? []
                    const main = keyboards.find(keyboard => keyboard.main) ?? keyboards[0]
                    root.capsLock = main?.capsLock ?? false
                    root.keymap = main?.active_keymap ?? ""
                    root.layouts = String(main?.layout ?? "").split(",").filter(name => name !== "").length || 1
                } catch (error) {
                    console.warn("Lock: cannot read the keyboards:", error)
                }
            }
        }
    }

    readonly property Timer keyboardPoll: Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.locked
        onTriggered: root.keyboardReader.running = true
    }

    // ── UNLOCKING ───────────────────────────────────────────────────────────

    // The password conversation ends here. The surface relaxes its blur while
    // `leaving`, and the lock falls once it has.
    function release(): void {
        if (root.leaving)
            return
        root.leaving = true
        root.leave.restart()
    }

    readonly property Timer leave: Timer {
        interval: Theme.durationMorph
        onTriggered: {
            if (root.pam.active)
                root.pam.abort()
            root.locked = false
            root.rest()
            root.forget()
            root.unlocked()
        }
    }
}
