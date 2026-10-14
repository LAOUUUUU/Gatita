# 012: Unreal Engine support (plan, not built)

**Status:** plan only. Written 2026-10-14. Shared design and the order: [010](010-game-engines-overview.md). **Step 7** of 7, the hardest.

## Goal

On the Mac, Gatita Code edits an Unreal project's C++ and config files, and drives the open Unreal Editor (actors, materials, Blueprints, tests) through Epic's own MCP plugin.

## Unreal in short

- C++ and Blueprints. The current docs are for **5.8**. 3% of GMTK Game Jam 2026 entries used it; Unreal is far bigger among professional studios, but I did not verify those survey figures (see [010](010-game-engines-overview.md)).
- Installed through the Epic Games Launcher (cask `epic-games` 20.3.3). Epic says the editor ships as universal binaries for macOS. Not installed on this Mac.
- **This Mac is outside Epic's table.** For 5.8 Epic lists macOS Sonoma 14.5 or later (Sequoia 15 recommended) and Xcode 26.0 to 26.1.1, and warns that "Xcode 26.4 is not compatible". This Mac runs macOS 27.0.1 and Xcode 27.0. Building C++ here is unproven; using the prebuilt editor for Blueprints and MCP may still work. Only a real run tells.
- Default install folder on a Mac is `/Users/Shared/Epic Games/UE_5.x/` with the editor binaries under `Engine/Binaries/Mac/` (a third-party tool's default and a forum answer; Epic's page does not state it, so unverified). The folder name has a **space**, which Gatita's allowed commands can't hold (they have no quoting).

## What exists for AI tools today (2026-10-14)

- **Epic's Unreal MCP plugin (Experimental).** Plugin ID `ModelContextProtocol`, in the 5.8 docs:
  - Turn it on in Edit, Plugins ("Unreal MCP"), also enable "All Toolsets", restart, then Editor Preferences, General, Model Context Protocol, **Auto Start Server** (or run `ModelContextProtocol.StartServer [port]` in the console).
  - It is an MCP server inside the editor at `http://127.0.0.1:8000/mcp`. **HTTP and SSE only; stdio and WebSocket are not supported.**
  - `ModelContextProtocol.GenerateClientConfig <ClaudeCode|Cursor|VSCode|Gemini|Codex|All>` writes a `.mcp.json` into the project root.
  - Localhost only; non-loopback `Origin` headers are rejected. **No authentication.** Epic says it is not safe to expose beyond the machine.
  - Tool calls run one at a time on the game thread. "Tool search mode" (on by default) shows three meta-tools: `list_toolsets`, `describe_toolset`, `call_tool`. Shipped toolsets named on the page: SceneTools, ActorTools, MaterialInstanceTools, ObjectTools.
  - Epic marks it Experimental: "many features are incomplete, and APIs and data formats may change". The page does not mention macOS either way.
- **Python scripting (5.8 docs).** Needs the Python Editor Script plugin (and Editor Scripting Utilities for the first form): `UnrealEditor-Cmd <project>.uproject -ExecutePythonScript="<file>"`, or headless `… -run=pythonscript -script="<file>"` (this form does not load a level on its own). The editor closes after the script runs.
- **Automation tests** run with `-ExecCmds="Automation RunTests <filter>; Quit" -unattended -nopause -nullrhi`. That form is from a third-party skill page and is **unverified** against Epic's docs.
- **Community MCP servers:** IvanMurzak/Unreal-MCP (47★, Apache-2.0, beta, UE 5.7, a C++ plugin plus a .NET sidecar) and chongdashu/unreal-mcp (2,097★, no license, last pushed 2025-04-22, so stale). An earlier session found "Unreal Engine Skills" from Epic in Claude's plugin catalog; not re-checked.

## Routes

1. **Editor tools: an HTTP server entry, `{"url": "http://127.0.0.1:8000/mcp"}`.** `MCPHub` already accepts a `url` entry (http or https) and, unlike local servers, works in **every build**. So this route is a preset and plain messages, not new protocol code. The `.mcp.json` the plugin writes has the same `mcpServers` shape as Gatita's `mcp.json`, so an "Import from this project" button (asks first, lists the servers) would fit. Because the server has no authentication, every call asks, and the server is never Trusted by default.
2. **Project files.** C++ under `Source/`, `*.Build.cs`, `*.Target.cs`, `Config/*.ini`, and the `.uproject` (JSON). Blueprints, maps and materials (`.uasset`, `.umap`) are **binary**: Gatita can't read or edit them as files. Use route 1 or a Python script for those.
3. **Headless commands.** `UnrealEditor-Cmd` for Python and tests, and Unreal Build Tool for C++ (heavy, needs a supported Xcode). The Derived Data Cache and logs live under `~/Library`, which the sandbox blocks, and the install path has a space. Not workable in the sandbox as it is.

## Detection

A `*.uproject` file at the project root. The chip reads `EngineAssociation` from it ("Unreal 5.8").

## Skill (`/unreal`)

It teaches the layout, "binary assets are edited through the editor tools, not as files", "C++ changes need a build, and Live Coding does not pick up new `UFUNCTION`s", "one tool call at a time", and the meta-tools (`list_toolsets`, `describe_toolset`, `call_tool`). Details come from Epic's docs when it is built.

## Milestones (each starts with a failing test)

*Phase A: needs no Unreal.*
1. The Unreal marker for `GameProject`, the chip, and the `/unreal` skill. C++ coloring already exists.
2. A mock **HTTP** MCP server in `Tests/MockServer` (the current mock is stdio only), then the "Add Unreal" preset and the project `.mcp.json` import, with messages for "plugin off", "server not started" and "editor closed".

*Phase B: needs a Mac that Epic supports.* Lao installs the launcher and an engine.
3. A real run: the handshake with swift-sdk 0.12.1, the real tool list, and one harmless call.
4. Whether the prebuilt editor runs on macOS 27 at all, and whether C++ builds with Xcode 27.

*Phase C: only on a yes.* Anything that cooks or packages a game.

## Limits and risks

- Experimental plugin, no authentication, calls one at a time. Unproven on this Mac's OS and Xcode.
- The largest install of any engine here, and it may not run (Phase B finds out).
- `MCPHub` drops pictures, so viewport screenshots would not show.
- Binary assets mean the files route cannot help with most game content.

## Decisions needed

- Do you want Unreal at all, given the Mac question? A second Mac or an older macOS is outside Gatita's scope.
- Should Gatita import a project's `.mcp.json`? It is convenient, but a project from someone else could name a command to run, so it must always ask and show the command first.

## Sources

- [Unreal MCP in Unreal Editor](https://dev.epicgames.com/documentation/unreal-engine/unreal-mcp-in-unreal-editor) (5.8 docs: the plugin, URL, limits, security)
- [macOS development requirements for Unreal Engine](https://dev.epicgames.com/documentation/unreal-engine/macos-development-requirements-for-unreal-engine) (the version table, universal binaries)
- [Scripting the Unreal Editor using Python](https://dev.epicgames.com/documentation/unreal-engine/scripting-the-unreal-editor-using-python) (5.8 docs: the two command-line forms)
- GitHub API, 2026-10-14: IvanMurzak/Unreal-MCP, chongdashu/unreal-mcp
- The install path and the test command line: a search summary of third-party pages, **unverified**
- `brew info --cask epic-games`, 2026-10-14
