# 008: A quick panel with a global shortcut, and no new libraries

**Status:** accepted (2026-10-13)

## Context

The open-source Swift chat apps the user pointed to have a floating panel you open from any app: Enchanted's "Spotlight panel" (⌃⌘K) and Onit's chat window (⌘0). Lao asked for that popout, in Gatita's own style.

A global shortcut is often added with a library (KeyboardShortcuts, HotKey) or with an event tap, which needs Accessibility permission.

## Decision

- The shortcut is ⌃⌘G, registered with Carbon's `RegisterEventHotKey` (`macOS/GlobalHotKey.swift`). It needs no permission, works in the App Sandbox, and adds no dependency. If another app holds the shortcut, the panel still opens from the Chat menu, and the log says so.
- The panel is a borderless, non-activating `NSPanel`, so it takes typing without bringing Gatita's main window forward. It keeps its top edge fixed as the answer grows, and Escape closes it.
- It answers in Chat mode with the connectors you turned on, your instructions, and an optional skill. It does not save anything until you press "Open in Gatita", which makes a saved chat in Chat.
- Ideas came from Enchanted (Apache-2.0) and Onit; no code was copied.

Later the same day Lao asked for ⌘ pressed twice as well. That cannot be a Carbon hot key, so it uses a listen-only `CGEventTap` on the modifier keys. Apple's guidance is that this needs Input Monitoring, which works in the App Sandbox, whereas a global `NSEvent` monitor needs Accessibility. ⌃⌘G stays, since it needs no permission.

Lao then asked for screenshots "the way Claude has it". Claude's quick entry starts in screenshot mode on its double-tap shortcut: drag an area or click a window, and it is attached. Gatita does the same on ⌘⌘ (a setting turns it off), and ⌃⌘G opens the plain panel. The first version hid the panel and used the system's crosshair (`screencapture -i`); Lao wanted the panel to stay on screen and be left out of the picture, which that tool cannot do. So Gatita draws its own picker (a dimmed overlay: drag an area or click a window) and captures with ScreenCaptureKit, excluding Gatita's own windows (Lao confirmed leaving out the main window too is what they want).

## Consequences

- Screenshots need Screen Recording permission, which ad-hoc builds also lose on every rebuild.

- ⌘⌘ needs Input Monitoring. Gatita asks once on its own; after that, Settings shows the state and opens the right page. Ad-hoc signed builds lose the permission on every rebuild, since macOS ties it to the build's code hash.

- The shortcut cannot be changed yet. A settings field for it is a possible follow-up.
- Reading the selected text of another app (as Onit does) would need Accessibility permission, so the panel uses the clipboard instead.
