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
