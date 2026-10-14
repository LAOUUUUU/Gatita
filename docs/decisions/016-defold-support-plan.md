# 016: Defold support (plan, not built)

**Status:** plan only. Written 2026-10-14. Shared design and the order: [010](010-game-engines-overview.md). **Step 4** of 7.

## Goal

On the Mac, Gatita Code edits a Defold project's Lua scripts and builds or bundles it with Defold's own command-line builder.

## Defold in short

- Lua. Latest release **1.14.0** (2026-10-12), 6,379★. The editor is cask `defold` (1.14.0); the macOS download is 297 MB for Apple silicon, and `bob.jar` is another 219 MB. Not installed here.
- A light 2D-first engine with a small, active community. I found no reliable usage share (see [010](010-game-engines-overview.md)).
- Its projects are made of text files (`game.project` and the script, collection and GUI files), but I have not seen one yet, so I'll check the exact formats on first install.

## What exists for AI tools today (2026-10-14)

- No official MCP server found.
- Community: **defold-mcp** by rochana-sadila, a stdio server whose listing says it lets an agent inspect a project, scaffold one, write scripts, edit collections, build with `bob.jar`, run the game headlessly, and run a Lua test suite. It shells out only to `java -jar bob.jar` and `dmengine_headless`. A second project (ChadAragorn's) uses `DEFOLD_PATH` and `BOB_PATH` variables. Both drive the project on disk; neither controls a running editor. Their upkeep is **unverified**.
- **`bob`** is Defold's command-line builder. From the manual: it builds data, makes archives and creates standalone bundles; it needs **OpenJDK 25**; get `bob.jar` from the Defold GitHub release. The manual's example: `java -jar bob.jar --archive --platform x86_64-macos resolve distclean build bundle`. Platform names for a Mac are `x86_64-macos` and `arm64-macos`. Other flags: `--bundle-output`, `--variant debug|release|headless`. `resolve` downloads library dependencies.
- This Mac has **Java 25.0.4** (an Oracle GraalVM build). The manual names OpenJDK builds from Microsoft and Adoptium; whether GraalVM works with `bob` is unverified.

## Routes

1. **Editor tools:** none worth building first. The community server is the only candidate, and it works on files, so it adds little over route 2 and 3.
2. **Project files.** Lua scripts (`.script`, `.gui_script`, `.render_script`, `.lua`) edited directly; the Lua family that the Roblox work added colors them. Collections and game objects are text too, but read them before editing.
3. **Commands: `bob`.** An allowed entry would start `java -jar /absolute/path/to/bob.jar` (no `~`, no quotes). `build` and `bundle` write into the project's `build/` folder, which the sandbox allows. `resolve` needs the network, so it can't run there. Whether `bob` also wants to write elsewhere in `~/Library` is a real test (Phase B).

**Web target.** `bob` makes an HTML5 bundle with `--platform wasm-web` (a `wasm_pthread-web` architecture also exists). Details: [018](018-web-builds-and-webgl-plan.md).

## Detection

A `game.project` file at the root. The chip reads the project title if present.

## Skill (`/defold`)

The file layout; Lua with Defold's message and lifecycle functions (`init`, `update`, `on_message`, `on_input`), whose exact names come from the Defold manual when the skill is built; "run `bob` to check a build if the command is allowed"; and "leave `build/` and `.internal/` alone".

## Milestones (each starts with a failing test)

*Phase A: needs no Defold.*
1. The Defold marker for `GameProject`, the chip, and the `/defold` skill. Lua coloring exists.

*Phase B: needs Defold and `bob.jar`.*
2. Install the editor (`brew install --cask defold`), download `bob.jar` from the release, make a sample project.
3. The sandbox replay of `java -jar bob.jar … build bundle`. Choose A, B or C from [010](010-game-engines-overview.md), then add the allowed entries as a plugin.
4. Decide whether the community MCP server earns a preset.

*Phase C: only on a yes.* Publishing or store bundles.

## Limits and risks

- `bob` needs the right JDK, and which JDK is right depends on the Defold version (the manual lists older ones for older releases).
- `resolve` needs the network, so a project with library dependencies can't build entirely inside the sandbox.
- The community MCP servers are small and unvetted.

## Decisions needed

- Do you want to make games in Defold? It is lower on the list than Godot, Unity, Bevy and the web engines.

## Sources

- [Defold manual: Bob the builder](https://defold.com/llms/manuals/bob.md) (everything about `bob`), read 2026-10-14
- GitHub API, 2026-10-14: defold/defold (1.14.0, 6,379★)
- [defold-mcp listing](https://glama.ai/mcp/servers/rochana-sadila/defold-mcp) (read through a search summary; the repo itself was not opened)
- `brew info --cask defold`, 2026-10-14; `java -version` on this Mac
