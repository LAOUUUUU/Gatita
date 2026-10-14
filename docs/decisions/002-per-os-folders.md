# 002: One folder per operating system for OS-only code

**Status:** accepted

## Context

Most of Gatita is shared. Some code only builds on one system: the command runner, the web check, the GitHub and Calendar connectors, the menu bar, and the pull-request sheet are macOS-only. The watch code is watchOS-only.

## Decision

- `Shared/` holds everything that builds on more than one platform. Platform checks (`#if os(...)`) stay inside those files where a few lines differ.
- `macOS/` holds files that only make sense on the Mac. They are registered with the Gatita target as a synchronized folder.
- `watchOS/` holds watch-only code. It is not yet in a built target.
- `iOS/`, `visionOS/`, and `tvOS/` are reserved for OS-only code. They are empty for now, so they are not in the Xcode project. Git does not track empty folders, so a folder appears in the repo once it has a file.
- `App/` holds the app entry point and the asset catalog.

## Consequences

- A reader can see from the folder whether a file is Mac-only.
- Moving a file between folders does not change the code: Swift refers to types by name. Only paths in scripts need updating (the harness does).

## Update, 2026-10-14

- `iOS/`, `iPadOS/`, and `visionOS/` are now in the Xcode project as synchronized folders of the Gatita target, like `macOS/`. `iPadOS/` is new: iPhone and iPad are one build, so it is for code only the iPad uses, which also checks the device at run time.
- Like `macOS/`, every file in them wraps itself in `#if os(...)`, since all folders build for every platform. Xcode can limit a file to some platforms, but only file by file in the project, which would undo the point of synchronized folders.
- The big single-OS parts of `Shared/` moved out: whole types (`MCPProcess`, the Project and Quick panel settings pages), Mac-only work behind small helpers (`GitCommand`, `MacLaunch`), the Watch link (`HostSession+Watch`), and the chat window's two layouts (`MacChatLayout`, `TouchChatLayout`). Short `#if` tweaks inside views stay in `Shared/`, and so does `TaskRegistry`'s split, which would have meant exposing its private bookkeeping.
- Empty folders keep a `.gitkeep` so they exist in the repo, and the app target skips it.
