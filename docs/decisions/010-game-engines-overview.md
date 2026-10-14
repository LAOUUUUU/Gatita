# 010: Game engine support (overview and order)

**Status:** plan only. Nothing here is built. The Roblox first step is the only game support so far ([006](006-roblox-support-plan.md)).
**Written:** 2026-10-14. The facts come from primary pages and GitHub, read on 2026-10-14 (sources at the end and in each plan). What I could not check is marked "unverified".

## Goal

Gatita Code helps build games in the engines people really use, on the Mac. Each engine has its own plan:

| Step | Plan | Engine |
|---|---|---|
| 1 | [017](017-web-engines-support-plan.md) | Web engines: PlayCanvas, Phaser, three.js, Babylon.js |
| 1 | [018](018-web-builds-and-webgl-plan.md) | Web builds and WebGL: the browser target of most engines below |
| 2 | [015](015-bevy-support-plan.md) | Bevy (Rust) |
| 3 | [013](013-godot-support-plan.md) | Godot |
| 4 | [016](016-defold-support-plan.md) | Defold |
| 5 | [014](014-gamemaker-support-plan.md) | GameMaker |
| 6 | [011](011-unity-support-plan.md) | Unity |
| 7 | [012](012-unreal-support-plan.md) | Unreal Engine |

The steps run web first, then the engines from easiest to hardest for Gatita to support (see "Order" below). Step 0 is the shared groundwork. The file numbers are only names, not the order.

This page holds what they share, the comparison, the order, and the engines I left out.

## What every plan reuses from Roblox

The Roblox first step is built and merged (commit `8775689`): Luau coloring, `RobloxProject.detect`, a "Roblox" chip in the project bar, and the `/roblox` skill. Each engine repeats the same four pieces:

1. **Detect the engine** from file names alone and show a chip. `RobloxProject` would become a `GameProject` with an `engine` field and a list of markers per engine (each plan lists them). Same limits as now: four folder levels, 2,000 entries, no hidden folders, off the main actor. When markers overlap (a Godot project with a Rust extension also has a `Cargo.toml`), an engine's own file wins over a generic one: `project.godot`, `*.uproject`, `ProjectSettings/ProjectVersion.txt`, `*.yyp`, `game.project` and `*.project.json` beat `Cargo.toml` and `package.json`.
2. **A skill** (`/godot`, `/unity`, …) that teaches the engine's file layout, which edits are safe, and how to check work.
3. **Code coloring** where Gatita lacks it. The tokenizer already covers C#, C++, Rust, Java, Kotlin, Lua/Luau, JavaScript/TypeScript and more. It does not know **GDScript** or **GML**.
4. **Three routes, in this order of preference:** tools inside the running editor (MCP or HTTP), the project's own files, then headless commands. The skill tells the model to use what is listed.

## What Gatita's design forces on every plan

- **MCP.** `MCPHub` talks to local stdio servers (Mac, Debug build only) and to HTTP servers (any build). Each call asks first unless the server is marked Trusted. Pictures from a tool are dropped, and a tool line shows only each argument's top-level type.
- **Commands run in a sandbox:** no network, and writes only to the project, `/private/tmp`, `/private/var/folders`, `~/Library/Developer` and `~/Library/Caches`. I replayed that profile on this Mac on 2026-10-14:

| Test inside the sandbox | Result |
|---|---|
| `cargo build`, no dependencies | works |
| `cargo build`, one registry dependency | fails (no network). `cargo build --offline` works when the crates are already cached |
| `npm run build` (runs node) | works |
| a program listening on localhost | fails (`EPERM`) |
| creating a folder in `~/Library/Application Support` | fails (not permitted) |

  Compiling and checking code works. Anything that **listens** (dev servers, an engine's remote API) or **keeps user data under `~/Library`** (Godot, Unity, Unreal and GameMaker all do) will probably fail until the sandbox changes. Each plan says what to test first.
- **Allowed commands are plain argument lists with no quotes,** so a path with a space can't be written. Unreal's default install folder, "Epic Games", has one.
- **No engine is installed here.** The Mac has Xcode, cargo, node, Java (JDK 25) and Python. Bevy and the web engines can be tried for real on this Mac today; the others need an install, which is Lao's call.

## The sandbox question (Unity, Unreal, Godot, GameMaker)

Editor tools are fine, since MCP servers run outside the command sandbox. The headless commands are the problem. Options:

- **A. Keep the sandbox.** Use MCP/HTTP and the files only. Headless builds and tests stay manual.
- **B. Let named commands run outside the sandbox,** only while "Ask before each command" is on, with Allow once but never "Always allow". This changes the safety model, so it is a decision and not a default.
- **C. Test first.** When an engine is installed, run its headless commands through the replayed profile and see what really fails. Some may pass (a Godot `--check-only` might need no user data).

My suggestion: A now, C when an engine is installed, and B only if C shows it is needed.

## The web is a build target for most of them

WebGL is the browser's graphics API (WebGL 2.0 is derived from OpenGL ES 3.0), and WebGPU is its newer sibling. Unity's Web platform, Godot's Web export, Bevy in WASM and Defold's HTML5 bundle all end up in a browser, and the web libraries in [017](017-web-engines-support-plan.md) draw with it. So [018](018-web-builds-and-webgl-plan.md) covers it once for everyone: raw WebGL and shaders, exporting an engine's game to the web, and a way to show a built web game inside Gatita with no server. I tested on this Mac that WebKit (the engine behind Gatita's HTML preview) runs WebGL 2, and that WebGPU appears only when a page has a secure origin.

## The engines side by side

| | Language | Editor on Mac | Project files | Official AI hooks | Community hooks | Fit for Gatita |
|---|---|---|---|---|---|---|
| **Godot** 4.7.2 | GDScript, C# | yes (`Godot.app`) | text | none | MCP servers (godot-ai, godot-mcp) | **best** |
| **Unity** 6.3 LTS | C# | yes | C# plus YAML assets and `.meta` files | Unity CLI (experimental): `unity test`, `recompile`, `command`, `eval`, `mcp` | unity-mcp (14.9k★) | good, heavy |
| **Unreal** 5.8 | C++, Blueprints | yes, with caveats | C++ text; assets binary | Unreal MCP plugin (Experimental, HTTP) | unreal-mcp (small) | partial |
| **GameMaker** | GML | yes | text (`.yyp`, `.yy`, `.gml`) | `gm-cli`, with an MCP mode | a few | good |
| **Bevy** 0.20 | Rust | n/a (cargo) | code only | none | `bevy_brp_mcp` | good, testable today |
| **Defold** 1.14 | Lua | yes | text | none | `defold-mcp` | good |
| **Web engines** | JS/TS | n/a (node) | code | PlayCanvas Editor MCP | few | good, testable today |

Use among game-jam entries (GMTK Game Jam 2026, Game World Observer, 2026-07-29): Godot 47% (it was 16% in 2022), Unity 34%, GameMaker 5%, Unreal 3%. Jams favor small games, so this says little about big studios. I saw other reported figures (the GDC 2026 survey, Steam releases) but did not check them at the source, so they are not used. I found no reliable share for Bevy or Defold.

Unreal and this Mac: Epic's table for 5.8 lists macOS Sonoma 14.5 (Sequoia 15 recommended) and Xcode 26.0 to 26.1.1, and says Xcode 26.4 is not compatible. This Mac runs macOS 27.0.1 and Xcode 27.0, which the table does not list.

## Order: web first, then engines from easiest to hardest

Lao asked for the web engines first, since they need the web-side support (WebGL, previews), and then the game engines from easiest to hardest. "Hardest" here means **hardest for Gatita to support**: new code, installs, sign-ins and unknowns. It does not mean hardest to learn. The reasons below come from the checks in this page, and each one can be re-sorted.

| Step | Plan | Engine | Why it sits here |
|---|---|---|---|
| 0 | this page | Groundwork | `GameProject` replaces `RobloxProject` (Roblox keeps working), plus the sandbox-replay checklist. Small, and every later step reuses it. |
| 1 | [017](017-web-engines-support-plan.md) | Web libraries: Phaser, three.js, Babylon.js, PlayCanvas | **Easiest of all.** Node and npm are already here, `npm run build` works in the sandbox (tested), and JS/TS coloring exists. No engine to install. It needs detection from `package.json`, a skill and a chip. The PlayCanvas MCP is an optional extra. |
| 1 | [018](018-web-builds-and-webgl-plan.md) | WebGL and web builds | Shader coloring, a WebGL 2 check of Gatita's own preview, and a skill are small, and WebKit already runs WebGL 2 here (tested). **The build-folder preview is the hard part of this step:** a new security surface that needs its own sign-off, so it comes last within the step. |
| 2 | [015](015-bevy-support-plan.md) | Bevy | **Nothing to install.** Cargo, clippy and rustfmt are here, and `cargo … --offline` works in the sandbox (tested). Rust coloring exists. The costs are API churn, slow first builds, and running the game outside the sandbox for the live link. |
| 3 | [013](013-godot-support-plan.md) | Godot | One small install (162 MB download), no sign-in, all text files, an offline command line. New work: GDScript coloring. Unknown until installed: whether Godot's user-data folder breaks it in the sandbox. |
| 4 | [016](016-defold-support-plan.md) | Defold | A JDK is here. Heavier than Godot (297 MB editor plus a 219 MB `bob.jar`), no official AI tools, and `resolve` needs the network. No new coloring (Lua exists). |
| 5 | [014](014-gamemaker-support-plan.md) | GameMaker | The official `gm-cli` helps (MCP, no IDE needed) and Node is here. But GML coloring is new, it downloads toolchains (network), and the tool is young. |
| 6 | [011](011-unity-support-plan.md) | Unity | Big installs (the CLI plus an Editor) and a Unity ID sign-in. The CLI is experimental, and its commands reach the Editor over localhost, which the sandbox blocks. |
| 7 | [012](012-unreal-support-plan.md) | Unreal | **Hardest.** The biggest install, binary assets, C++ builds that need an Xcode Epic's table does not list for this Mac, an install path with a space, and an Experimental plugin. If it runs, its HTTP MCP is the easiest connection of all. |

Roblox's next steps (the Studio preset and Open Cloud, [006](006-roblox-support-plan.md)) stay parked until you install Studio or make an API key.

Popularity is a separate question from effort. By the GMTK 2026 numbers Godot (47%) and Unity (34%) matter most, so if you care about reach more than effort, Godot could move up ahead of Bevy.

## Engines I left out, and why

- **Flax Engine:** has a native Mac editor (arm64, macOS 11.7 or later, per its docs) but a small community. A good next plan if you want one.
- **O3DE:** its release page lists Windows and Linux builds only, and macOS is described as an experimental host platform.
- **Stride:** no native Mac editor that I could find (building projects from a Mac is being added).
- **Not researched:** Cocos Creator, LÖVE (cask `love` 11.5), Ren'Py (cask `renpy` 8.5.3), RPG Maker, Construct, and code frameworks such as MonoGame, FNA, libGDX and raylib. Most are Lua, Python or C# code that the files route already handles.
- **Platforms like Roblox:** Minecraft modding (Fabric, NeoForge, Paper plugins) and Fortnite's UEFN. Not researched. Minecraft is the likeliest next one, given your own Minecraft projects.
- **Apple's SpriteKit, RealityKit and Metal:** already covered by the Swift and Xcode support Gatita has.

## Decisions needed

1. Which engines do you actually want to make games in? The order above is by effort; your own interest may move one up.
2. The sandbox: A, B or C above?
3. Plan Minecraft modding next, like Roblox?
4. Replace `RobloxProject` with one `GameProject` now, or keep one detector per engine?
5. Add `cargo … --offline` to the built-in allowed commands, or ship it as a plugin?
6. Keep these plans local, or commit them to the public repo?
7. Should web games run inside Gatita (a preview of a built folder), or is opening them in your browser enough? ([018](018-web-builds-and-webgl-plan.md))

## Sources

- GMTK Game Jam 2026 shares: [Game World Observer, 2026-07-29](https://gameworldobserver.com/2026/07/29/unity-is-no-longer-the-leader-godot-has-become-the-most-popular-engine-at-gmtk-game-jam-2026)
- Unreal on macOS: [Epic, macOS development requirements](https://dev.epicgames.com/documentation/unreal-engine/macos-development-requirements-for-unreal-engine)
- Flax on Mac: [Flax docs, Editor on Mac](https://docs.flaxengine.com/manual/get-started/mac.html) (read through a search summary)
- O3DE platforms: [O3DE docs, supported platforms](https://docs.o3de.org/docs/welcome-guide/supported-platforms/) (read through a search summary)
- Versions and star counts: the public GitHub API, 2026-10-14 (godotengine/godot 4.7.2-stable; bevyengine/bevy v0.20.0; defold/defold 1.14.0; CoplayDev/unity-mcp v10.3.0)
- Homebrew cask versions: `brew info --cask`, local metadata, 2026-10-14
- The sandbox replay: run on this Mac on 2026-10-14 with the rules of `CommandPolicy.sandboxProfile`
- Each engine's own sources are at the end of its plan.
