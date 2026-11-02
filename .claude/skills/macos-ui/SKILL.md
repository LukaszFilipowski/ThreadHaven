---
name: macos-ui
description: Rules for placing and checking controls in the ThreadHaven macOS interface. Use before adding or moving any button, toggle, menu item or sidebar control, and before saying a UI change works.
---

# ThreadHaven UI rules

## Where controls go

- Every window-level action lives in the trailing toolbar group (`ToolbarItem(placement: .primaryAction)`), together with Workspace and New Chat. Do not use `.navigation` next to the window title: people look for buttons on the right and miss anything on the left.
- Order in the trailing group: view switches first (Private Mode), then windows (Workspace), then create actions (New Chat) last, at the edge.
- Actions on one chat belong in its row and its header: hover controls on the row, the same actions in the context menu, and buttons in the chat header. Never in the window toolbar.
- Every hover-only control (like ✕ Close) has a context-menu twin, because hover is invisible until you find it.
- Destructive actions (Close, anything that kills processes) ask for confirmation and say what will stop.

## How controls look

- A toggle shows its state: filled SF Symbol when on (`eye.slash.fill`), outline when off, and the toolbar highlight comes from using `Toggle`, not `Button`.
- Every toolbar item has a `Label` with a real title (it is read by VoiceOver and shown in "Icon and Text" mode) and a `.help` tooltip that says what it does, with its shortcut if it has one.
- New user-facing strings go through `String(localized:)` and get a Polish entry in `Resources/pl.lproj/Localizable.strings` in the same change.

## Checking a UI change

Build and tests passing is not enough. Before saying it works:

1. `make app`, then run the built copy next to the user's app with `open -n build/ThreadHaven.app`. Do not quit or restart the user's ThreadHaven without asking: chats in its embedded terminals die with it.
2. Find the main window id with `CGWindowListCopyWindowInfo`, keeping only layer 0 windows named "ThreadHaven" (tooltips are separate windows), and capture it with `screencapture -x -o -l <id>`. Look at the screenshot.
3. Drive controls through Accessibility, for example `click checkbox 1 of group 1 of toolbar 1 of window 1` of the process found by its pid, and screenshot both states.
4. Test destructive actions only on a throwaway chat started for the test, never on the user's running chats.
5. Quit the test copy when done.
