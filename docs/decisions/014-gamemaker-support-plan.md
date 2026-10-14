# 014: GameMaker support (plan, not built)

**Status:** plan only. Written 2026-10-14. Shared design and the order: [010](010-game-engines-overview.md). **Step 5** of 7.

## Goal

On the Mac, Gatita Code edits a GameMaker project's GML scripts, changes its resources (objects, sprites, rooms) without the IDE, and builds or runs it with GameMaker's own command-line tool.

## GameMaker in short

- GML (GameMaker Language). Made by Opera. **5% of GMTK Game Jam 2026 entries** (498 games), third after Godot and Unity.
- The IDE is cask `gamemaker` (2024.14.4.222). Not installed on this Mac.
- On 2026-04-30 Opera announced **GMRT** (a new runtime) and **GM-CLI** (a command-line toolchain that works with the old and new runtimes). The coverage says project files are now stored as plain text and that Claude Code is one of the first AI workflows built in. It also says JavaScript, TypeScript and C# support is planned for GMRT before the year is out, so the language story may change.

## What exists for AI tools today (2026-10-14)

- **The official `gm-cli`** (YoYoGames/gm-cli, Apache-2.0, 44★, pushed 2026-10-06; npm package `@gamemaker/gm-cli`). It needs Node.js, which this Mac has (v24.19.0). From its README:
  - `gm-cli init` makes a project from a blank game or a template and can set up GitHub pipelines and "AI agent integration (AGENTS.md, MCP, Claude config)".
  - `gm-cli run`, `compile` and `package`. Options include `--runtime=vm`, `--target=operagx` and `--toolchain=gms2@2024.14.3.260`. It "can automatically download the runtime and all other tools needed".
  - `gm-cli resourcetool` edits project files without the IDE. `gm-cli resourcetool eval "resource list"` is an example, and the README calls an AI agent using **`gm-cli resourcetool mcp`** the most convenient way.
  - `gm-cli manual` searches the GameMaker Manual by meaning; `login <key>` uses an access key; `gxgames` publishes to gx.games.
  - It gives a guest license automatically, so no sign-in is needed.
- **The older command-line tool, Igor,** is in GameMaker's manual ("Building & Testing via Command Line"). On a Mac its license folder is `~/Library/Application Support/GameMakerStudio2/`, and a command-line build needs a prior IDE login or an access key. Community notes show it run under Mono on macOS (2022 runtimes). `gm-cli` replaces the need to know any of that.
- **Community MCP servers** exist (darkw3bb/GameMaker-MCP-Server, `gms-mcp` on PyPI, a paid Windows tool). Not considered: the official one covers the same ground.

## Routes

1. **Editor tools: `gm-cli resourcetool mcp` as a stdio server in `MCPHub`** (Mac, Debug build). It edits project resources directly, so **no running editor is needed**, which makes it the easiest "editor route" of any engine here. Install a pinned version (`npm install -g @gamemaker/gm-cli@<version>`) and point the preset at it, instead of `npx …@latest`, which runs whatever is newest.
2. **Project files.** `.gml` scripts are text and can be edited freely. `.yyp` and `.yy` files describe resources as JSON and are easy to break: use the `resourcetool` tools for those.
3. **Headless commands:** `gm-cli compile`, `run` and `package`. They download runtimes (network) and `run` opens the game's window, so they cannot pass the sandbox. They need the sandbox decision in [010](010-game-engines-overview.md).

## Detection

A `*.yyp` file at the project root. The chip reads the project name and, if present, the runtime.

## GML coloring (new)

GML is C-like but has its own words (`var`, `function`, `with`, `global`, `self`, `other`, `repeat`, `until`, `#macro`, `#region`, and more). The keyword list is taken from GameMaker's manual **when it is built**, not from memory.

## Skill (`/gamemaker`)

The resource model (objects, events, rooms, sprites), "resource files are JSON: change them with `resourcetool`, not by hand", GML style, and how to compile if commands are allowed. `gm-cli manual` is a good thing to point the model at for GML questions once its output is seen.

## Milestones (each starts with a failing test)

*Phase A: needs no GameMaker.*
1. GML coloring.
2. The GameMaker marker for `GameProject`, the chip, and the `/gamemaker` skill.
3. A "GameMaker (gm-cli)" preset with plain messages ("gm-cli not installed", "Node.js missing"), tested against the stdio mock.

*Phase B: needs `gm-cli`.* Node is already here; `npm install -g` is a user action, since it runs third-party code.
4. `gm-cli init` in a scratch folder, then a real `resourcetool mcp` run to record its tool list and update the mock.
5. The sandbox replay of `compile`; decide A, B or C.

*Phase C: only on a yes.* `package` and `gxgames` (publishing to gx.games is outward-facing, like publishing a Roblox game).

## Limits and risks

- `gm-cli` is new (44★), so it will change. Pin it and record the version each step was tested with.
- It downloads and runs toolchains. The guest license terms are unread (unverified).
- The `.yy` files are the fragile part. Never hand-edit them without `resourcetool`.
- GMRT may change the languages and project layout during the year.

## Decisions needed

- Do you want to make games in GameMaker?
- Is installing `@gamemaker/gm-cli` globally on your Mac OK when we get to Phase B?

## Sources

- [YoYoGames/gm-cli on GitHub](https://github.com/YoYoGames/gm-cli) (README read 2026-10-14; Apache-2.0, 44★)
- [Opera press release: GameMaker launches GMRT](https://press.opera.com/?p=3924) and [Game Developer coverage](https://gamedeveloper.com/production/gamemaker-incorporates-claude-code-to-enable-ai-assisted-workflows) (both read through search summaries)
- [GameMaker Manual: Building and testing via command line](https://manual.gamemaker.io/monthly/en/Settings/Building_via_Command_Line.htm) (Igor; search summary)
- [GMTK Game Jam 2026 shares](https://gameworldobserver.com/2026/07/29/unity-is-no-longer-the-leader-godot-has-become-the-most-popular-engine-at-gmtk-game-jam-2026)
- `brew info --cask gamemaker`, 2026-10-14
