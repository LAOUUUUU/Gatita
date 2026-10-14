# 011: Unity support (plan, not built)

**Status:** plan only. Written 2026-10-14. Shared design and the order: [010](010-game-engines-overview.md). **Step 6** of 7.

## Goal

On the Mac, Gatita Code edits a Unity project's C# and text assets, checks that scripts compile, runs the project's tests, and, if wanted, drives the open Editor.

## Unity in short

- C#, Unity 6. **6.3 LTS** is the newest release and is supported until December 2027. 6.0 LTS support ends in October 2026 ([Unity 6 releases](https://unity.com/releases/unity-6)). Whether the 6.x macOS Editor runs natively on Apple silicon is reported inconsistently on Unity's forums, so check the release notes before installing (unverified).
- 34% of GMTK Game Jam 2026 entries used it, second to Godot.
- Not installed on this Mac. Installs: Unity Hub (cask `unity-hub` 3.22.2) or the Unity CLI (cask `unity-cli` 1.0.0-beta.13).
- Unity's manual says `-batchmode` use is governed by its Terms of Service unless separate commercial terms apply.

## What exists for AI tools today (2026-10-14)

- **Unity CLI (experimental).** macOS 14 or later. Free, and "separate from Unity AI": no Unity AI subscription is needed. Install with `curl -fsSL https://unity.com/install.sh | bash` or `brew install --cask unity-cli`. Commands from its reference that matter here:
  - `unity recompile` recompiles a running Editor's scripts and reports compile errors.
  - `unity test` runs Edit Mode and Play Mode tests through the Editor's test runner and writes an NUnit report. Exit code 8 means the tests ran and some failed; 6 means the run did not finish.
  - `unity build`, `unity run` (batch mode, or `--command` for a registered Editor command), `unity open`, `unity close`, `unity watch`.
  - `unity command` and `unity eval` drive the **running Editor** through the **Unity Pipeline package** (`com.unity.pipeline`, Unity 6.0 or later; add it with `unity pipeline install` after `unity auth login`). Unity says they are faster and use fewer tokens than MCP for agents that can run shell commands. The local pipeline server accepts localhost only.
  - `unity mcp` is the CLI's own MCP server and stays fully supported. `unity mcp configure <client>` rewrites a listed client's config; Gatita is not a listed client, so its entry would be made by hand.
- **The in-Editor MCP server is deprecated.** Unity's migration page says the MCP server in the `com.unity.ai.assistant` package is deprecated and the CLI replaces it. Unity's May 2026 blog and the 2.0 package docs still describe it (with a Unity Cloud project and an AI-tools trial or subscription). Do not build on it.
- **Community MCP packages are unaffected:** CoplayDev/unity-mcp (14,947★, MIT, v10.3.0, 2026-10-04) and IvanMurzak/Unity-MCP (4,452★, Apache-2.0).
- **Editor flags** (Unity 6 manual): `-batchmode -nographics -quit -projectPath <path> -executeMethod Class.Method -logFile <path> -buildTarget <target> -accept-apiupdate`. Tests: `-runTests -testPlatform EditMode|PlayMode -testResults <xml> -testFilter -testCategory -assemblyNames`.

## Routes

1. **Editor tools.** Two ways:
   - **`unity mcp` as a stdio server in `MCPHub`** (Mac, Debug build, outside the command sandbox). A "Unity" preset in Settings, MCP Servers. I did not find `unity mcp`'s exact arguments or its tool list in the pages I read, so both come from a real run (`unity mcp --help`).
   - **`unity command` and `unity eval` as shell commands.** Cheaper per Unity, but they connect to the Editor on localhost, which the command sandbox denies (tested: `EPERM`). They need the sandbox decision (B or C in [010](010-game-engines-overview.md)).
2. **Project files.** Edit C# under `Assets/`, and `Packages/manifest.json`. Never touch `Library/`, `Temp/` or `Logs/`. Every asset has a `.meta` file that holds its GUID; Gatita has no delete or move tool, so it can't split a pair. Scenes and prefabs are YAML text but fragile, so prefer Editor tools (route 1) for them.
3. **Headless commands.** `unity recompile`, `unity test`, `unity build`, or the raw Editor flags. They start or talk to the Editor, need a license, and write under `~/Library`, so they will not pass the sandbox as it is.

**Web target.** Unity's Web platform builds on WebGL 2 by default; WebGPU must be switched on and is experimental. Compressed builds need a matching `Content-Encoding` header from whatever serves them. Details, and the idea of previewing a built folder inside Gatita: [018](018-web-builds-and-webgl-plan.md).

## Detection

`ProjectSettings/ProjectVersion.txt` plus an `Assets/` folder. The chip reads the Editor version from that file ("Unity 6000.x").

## Skill (`/unity`)

It teaches the layout above, the `.meta` rule, "do not edit a scene or prefab as text unless asked", and "after editing scripts, run the recompile or test command if it is allowed, else say what to run". Unity coding practice is written from Unity's own docs when the skill is built, not from memory. Once route 1's tool names are known, the skill names them.

## Milestones (each starts with a failing test)

*Phase A: needs no Unity.*
1. The Unity marker for `GameProject`, the chip, and the `/unity` skill. C# coloring already exists.
2. A plugin of allowed commands (`unity recompile`, `unity test`), off by default, with the sandbox note beside it.

*Phase B: needs Unity.* Lao installs the Unity CLI and an Editor and signs in.
3. A real run of `unity mcp`: record its tool list, then add the preset and a mock server that copies the list.
4. The sandbox replay for `recompile`, `test` and `build`. Choose A, B or C from the result.

*Phase C: only on a yes.* Anything that builds a player.

## Limits and risks

- The CLI is **experimental**, and Unity says its docs may change. Record the CLI version each step was tested with.
- It needs a Unity ID sign-in (`unity auth login` opens a browser). Gatita never types credentials; the user signs in.
- The deprecated in-Editor server is still in older guides. The skill and the preset must not point to it.
- Community MCP packages install into the project from GitHub: third-party code running inside the Editor. Never mark one Trusted.
- Large downloads and a heavy Editor. The Mac architecture reports are unverified.

## Decisions needed

- Do you want Unity at all, and will you sign in with a Unity ID?
- The CLI route (`unity mcp`), a community package, or both?
- The sandbox option for `unity …` commands (see [010](010-game-engines-overview.md)).

## Sources

- [Unity CLI as the replacement for the in-Editor MCP server](https://docs.unity.com/en-us/unity-cli/replace-mcp-server-unity-cli) (the deprecation and the migration steps)
- [Use the Unity CLI](https://docs.unity.com/en-us/unity-cli/use-unity-cli) (experimental, macOS 14+, install, Homebrew cask)
- [Unity CLI reference](https://docs.unity.com/en-us/unity-cli/unity-cli-reference) (commands, exit codes)
- [Unity Pipeline package](https://docs.unity.com/en-us/unity-cli/unity-pipeline/unity-pipeline-package) (Editor 6.0+, local HTTP API, `unity pipeline install`)
- [Unity MCP, Assistant 2.0.0-pre.1](https://docs.unity3d.com/Packages/com.unity.ai.assistant@2.0/manual/unity-mcp-overview.html) (the older, deprecated server)
- [Unity blog, 2026-05-11](https://unity.com/blog/unity-ai-mcp-how-to-get-started) (its requirements and open-beta status)
- [Editor command line arguments, Unity 6](https://docs.unity3d.com/6000.0/Documentation/Manual/EditorCommandLineArguments.html)
- [Test Framework command line, 1.4](https://docs.unity3d.com/Packages/com.unity.test-framework@1.4/manual/reference-command-line.html)
- [Unity 6 releases](https://unity.com/releases/unity-6) (6.3 LTS, support dates)
- GitHub API, 2026-10-14: CoplayDev/unity-mcp, IvanMurzak/Unity-MCP
- The sandbox replay: [010](010-game-engines-overview.md)
