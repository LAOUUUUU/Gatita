# 001: Question-only hosts on iPhone, iPad, and Vision Pro

**Status:** accepted

## Context

A host holds the API key and runs the chat. On the Mac, a host can also read a project folder, edit files, run allowed commands, read GitHub, and create pull requests. Those tools need a Mac: they use `Process`, the macOS sandbox, `gh`, and a real project folder. An iPhone or Vision Pro has none of these.

Before this change, the iOS build still showed the project folder and the edit and command switches in Settings, so a saved path could turn file tools on there.

## Decision

`HostPolicy` (`Shared/Tools/HostPolicy.swift`) decides what a host can do:

- **Mac:** every tool, subject to the user's switches.
- **iPhone, iPad, Vision Pro:** no project folder. `ProjectTools` gets `root: nil`, so every file tool, command, and PR path is refused. Only the web reads connector and the ask, reports, and plugin skill tools remain.

GitHub and Calendar are marked `macOnly` and are hidden on the other hosts, in the composer, the settings, and the shop.

Settings on other hosts show a note instead of the folder and switches.

## Consequences

- A saved project path is ignored on any host except the Mac.
- A host with no folder can still use web connectors, so the policy is about capability, not about whether the chat works.
- The check is enforced in code (`ProjectTools.folder()`), not only in the UI, and the harness tests it (section 27).
