# 013: Godot support (plan, not built)

**Status:** plan only. Written 2026-10-14. Shared design and the order: [010](010-game-engines-overview.md). **Step 3** of 7, after the web work and Bevy. By popularity (47% of GMTK 2026 entries) it could move up.

## Goal

On the Mac, Gatita Code edits a Godot project's GDScript and scenes, checks scripts for errors, runs tests, and, if wanted, drives the open editor.

## Godot in short

- GDScript and C#. Latest release **4.7.2-stable** (2026-08-18); the docs are for 4.7. Open source (MIT), 118k★.
- **47% of GMTK Game Jam 2026 entries** used it (16% in 2022), more than any other engine there.
- Install: `brew install --cask godot` (cask 4.7.2) gives `/Applications/Godot.app`. Not installed here. The macOS download is 162 MB (191 MB with .NET).
- Its project files are text: `project.godot`, `*.tscn` (scenes), `*.tres` (resources), `*.gd` (scripts). That is why it fits Gatita so well.

## What exists for AI tools today (2026-10-14)

There is **no official Godot MCP server.** Community ones, from the GitHub API and search listings:

- **hi-godot/godot-ai:** 2,982★, MIT, v4.3.0 (2026-10-03), pushed 2026-10-14. A Godot editor plugin plus a Python server (FastMCP) that exposes the editor and scene tree, so the model can change the live editor. Listed on the Godot Asset Library.
- **Coding-Solo/godot-mcp:** 6,081★, MIT, last pushed 2026-04-16, no releases. A Node server that starts the editor, runs the project and reads debug output through the command line.
- **tomyud1/godot-mcp:** 434★, MIT, pushed 2026-08-24. A WebSocket bridge to an editor plugin.
- A paid "godot-mcp-pro" is also listed. Not considered.

Testing and linting tools:

- **GUT** v9.6.1 (2026-07-09): `godot -d -s --path "$PWD" addons/gut/gut_cmdln.gd` (its docs); exit code 0 when all tests pass, 1 when any fail.
- **gdUnit4** v6.2.2 (2026-10-07, MIT): Godot 4.3 to 4.7.x, with a command-line runner whose exact arguments I did not verify.
- **gdtoolkit** 4.5.0 (2025-10-09, MIT): `pip3 install "gdtoolkit==4.*"` gives `gdlint` and `gdformat`.

## Routes

1. **Editor tools: a community MCP server as a stdio entry in `MCPHub`** (Mac, Debug build). The editor-plugin kind (godot-ai) is the one that can change the open scene. Presets, never Trusted by default, pinned to a release. They install with `uvx` or `npx`, which run third-party code; the earlier community Roblox server was archived after its owner lost their npm keys, which is the risk to avoid.
2. **Project files: the strongest route.** The model reads and writes scripts and scenes directly. Cautions for the skill: leave `.godot/` (the import cache) and `*.import` files alone; scene files carry numbered resource ids, so make small edits and read the file right before editing; Godot 3 and 4 differ, so check the version in `project.godot` first.
3. **Headless commands** (4.7 docs): `--headless`, `--path <dir>`, `--script <file>` (the script must extend `SceneTree` or `MainLoop`), `--check-only` (parse for errors; used with `--script`), `--import`, `--export-release|--export-debug|--export-pack <preset> <path>`, `--quit`, `--quit-after <n>`, `--log-file <path>`. On a Mac the binary is `Godot.app/Contents/MacOS/Godot`. An allowed-command entry starts with the full path, `/Applications/Godot.app/Contents/MacOS/Godot` (no spaces, so it can be written).
   - **Sandbox:** these runs are offline, but Godot keeps user data under `~/Library/Application Support/Godot`, and the sandbox blocks writes there (tested with a plain folder). Whether `--check-only`, `--import` and GUT survive is a real test (Phase B). `--log-file` pointed into the project may help.

**Web target.** Godot's Web export uses WebGL 2.0 through the Compatibility renderer only (no WebGPU yet) and cannot export C# projects; threaded builds need cross-origin-isolation headers, the single-threaded default does not. Details: [018](018-web-builds-and-webgl-plan.md).

## Detection

A `project.godot` file at the root, or up to four folders down. The chip reads the version from it ("Godot 4.7").

## GDScript coloring (new)

GDScript is not C-like and is missing from the tokenizer. A new family: `#` comments, `"""` strings, `@annotations`, `$NodePath` and `%UniqueName`, and the keyword list taken from the GDScript reference page **when it is built** (not from memory). `*.tscn` and `*.tres` get a light INI-style pass for their `[node …]` lines.

## Skill (`/godot`)

The text-file layout above; typed GDScript; signals and `@export`; `res://` paths; Godot 3 versus 4; "never edit `.godot/`"; "after edits, run `--check-only` or the project's GUT tests if the commands are allowed, else say what to run".

## Milestones (each starts with a failing test)

*Phase A: needs no Godot.*
1. GDScript coloring.
2. The Godot marker for `GameProject`, the chip, and the `/godot` skill.
3. MCP presets for godot-ai and godot-mcp with plain messages ("not installed", "editor plugin off"), tested against the existing stdio mock.

*Phase B: needs Godot* (`brew install --cask godot`; the macOS download is 162 MB, or 191 MB with .NET, from the GitHub release).
4. The sandbox replay of `--headless --check-only`, `--import` and GUT. Choose A, B or C from [010](010-game-engines-overview.md).
5. A plugin of allowed commands from what passed. A first test project: the user's, or a generated one.
6. A live check of the editor-plugin route.

*Phase C: only on a yes.* Exporting builds.

## Limits and risks

- Every MCP server here is community-made, and most are young. Pin versions and never mark one Trusted.
- Scene files are text but order- and id-sensitive. A bad edit loads silently wrong.
- The sandbox may block even `--check-only`. Phase B finds out.

## Decisions needed

- Do you want to make games in Godot? It is the cheapest one to try.
- Which MCP server to start with: the editor-plugin kind (godot-ai) or the command-line kind (godot-mcp)?

## Sources

- [Godot command line tutorial, 4.7 docs](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) (every flag above)
- [GUT command line docs](https://gut.readthedocs.io/en/latest/Command-Line.html) (read through a search summary)
- GitHub API, 2026-10-14: godotengine/godot (4.7.2-stable), hi-godot/godot-ai (v4.3.0), Coding-Solo/godot-mcp, tomyud1/godot-mcp, bitwes/Gut (v9.6.1), MikeSchulze/gdUnit4 (v6.2.2), Scony/godot-gdscript-toolkit (4.5.0)
- [gdtoolkit README](https://github.com/Scony/godot-gdscript-toolkit) (`gdlint`, `gdformat`, install line)
- [GMTK Game Jam 2026 shares](https://gameworldobserver.com/2026/07/29/unity-is-no-longer-the-leader-godot-has-become-the-most-popular-engine-at-gmtk-game-jam-2026)
- `brew info --cask godot`, 2026-10-14; the sandbox replay in [010](010-game-engines-overview.md)
