# 006: Roblox support (partly built)

**Status:** updated 2026-10-14 after research (sources at the end). The same approach, for other engines, is in [010](010-game-engines-overview.md).
Built: Luau highlighting, the Roblox skill, Roblox project detection, and the project bar chip. Not built: the Studio
preset, Open Cloud, and publishing. Lao asked for only the built part for now, and said publishing is "not yet".

## Goal

On the Mac, Gatita Code helps build a Roblox game: read and edit the scripts, look at the place, run it in Studio,
and, only with approval and only if Lao later says yes, publish it.

## Routes

There are still three, in this order of preference, but they are **guidance, not a picker**. The Roblox skill tells
the model to use Studio's tools if they are listed, else edit the files in the project folder, else (later) use the
cloud tools. The project bar chip shows what was found. The model chooses among real tools.

1. **Studio's built-in MCP server (not built).** Studio ships it: turn it on under Assistant, then …, then Manage MCP
   Servers, then "Enable Studio as MCP server". macOS command `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`
   (no arguments), stdio. About 26 tools (read and edit scripts, search the game tree, run Luau, play-test, read the
   console, capture the screen, simulate input, insert assets). Every call needs a `studio_id` from
   `list_roblox_studios`. Gatita's `MCPHub` already speaks MCP, so **no new client is needed**: the work is an
   "Add Roblox Studio" preset in Settings, MCP Servers, with plain messages for "not installed", "turned off", and
   "Studio not open". Things to keep in mind:
   - Roblox documents no approval prompts of its own and warns that clients can read and change the open place.
     Gatita's per-call approval card is the only gate, so the server stays untrusted by default. (MCP tools ask per
     call; they do not follow the writes switch.)
   - Local MCP servers need the Debug build (App Sandbox off). A sandboxed Release build cannot start it.
   - Roblox's older Rust server (archived 2026-04-03) and the community npm server (archived 2026-06-06, installed
     with `npx @latest`) are not offered.
   - Not yet known: how it behaves when Studio is closed, and whether the handshake works with swift-sdk 0.12.1.
     Roblox Studio is not installed on Lao's Mac, so this needs a real run later.
2. **Project folder (built).** `RobloxProject.detect` finds a Rojo `*.project.json` or script files named for their
   type (`Main.server.luau`). Studio's Script Sync mirrors Script, LocalScript, ModuleScript and Folder instances to
   disk both ways and **ignores scripts with attributes or tags**; Rojo is the better choice when the files should be
   the source of truth. Edits reach Studio only while Rojo is serving or Script Sync is syncing, which Gatita can't
   see. The command sandbox denies network, so `rojo serve` and `wally install` can't run from Gatita; `rojo build`,
   `selene`, `stylua --check`, and `luau-analyze` could, once installed (none are on Lao's Mac).
3. **Open Cloud (not built).** An API key in the Keychain, never shown to the model, in no log or failure report.
   Mac only unless Lao decides otherwise. Scope names have changed over time, so read them from the docs or a 403
   rather than from samples.
   - **Luau Execution (stable):** run a script headlessly in a place (up to 4 MB, 5 min, 10 incomplete tasks per
     place, creating a task is limited to 5 a minute). A script can call `SavePlaceAsync` and reach DataStores, so a
     "run" can change a live game: test place only, and every run asks and shows the script.
   - **Engine instances (beta):** read and update Script, LocalScript and ModuleScript only; needs a collaborative
     session; a script open in Studio can't be updated; 200 KB bodies.
   - **Publish a place version (beta):** `POST /universes/v1/{universeId}/places/{placeId}/versions`, scope
     `universe-places:write`, `versionType` of `Saved` (not live) or `Published` (live). Not wanted yet.

## Milestones (each starts with a failing test)

Done (2026-10-14):
1. **Luau highlighting.** `--` and `--[[ ]]` comments, long strings, backtick strings, Lua's keywords, and `type`,
   `export`, `continue`, `const` as keywords only where used as one. `//` is floor division, not a comment (before,
   `lua` blocks were colored like C).
2. **Roblox skill, project detection, chip.** `Skills.swift`, `Shared/Roblox/RobloxProject.swift`, `macOS/ProjectBar.swift`.

Next, each needing Lao's go-ahead first:
3. **Studio preset** (see route 1), tested against a new `Tests/MockServer/mock_studio_mcp_server.py` that copies the
   documented tool names and the `studio_id` rule.
4. **Open Cloud, read and test:** place info, read and list scripts, and run Luau in a configured test place.
5. **Publish,** only if Lao says yes: `Saved` by default; `Published` needs a second approval that names the place;
   refuses any place not on the list; never retries by itself. A person must read Roblox's Terms of Use first (the
   help-center page sits behind a Cloudflare check, so they were not read).

Dropped from the first plan: a hand-built JSON-RPC stdio client, a hard route picker, and DataStore tools (player
data, separate scopes).

## Limits

- Gatita can't run Luau. A script that uses Roblox's objects runs only inside Roblox (Studio, or a place through
  Luau Execution).
- iPhone and iPad can't run Studio. The PC tab sends chats to the Mac, so it can reach the Mac's Studio tools.
- `screen_capture` returns a picture, which `MCPHub` drops ("a picture, not shown"). Showing it is a later option.
- Tool lines show only each argument's top-level type, so list-of-object arguments (keyboard and mouse input) lose
  their shape. Also a later option.

## Decisions

- 2026-10-14, Lao: build only the first two milestones now. Publishing: not yet.
- Defaults unless Lao says otherwise: Open Cloud on the Mac only; no DataStore tools.

## Sources

All read on 2026-10-14 unless noted.

- [Connect to the Roblox Studio MCP server](https://create.roblox.com/docs/en-us/studio/mcp) (26 tools, macOS path, trust warning)
- [Script Sync](https://create.roblox.com/docs/en-us/scripting/sync) (file names, conflicts, what it ignores)
- [Luau Execution API](https://create.roblox.com/docs/en-us/cloud/reference/features/luau-execution), [Places API](https://create.roblox.com/docs/en-us/cloud/reference/features/places), [Engine instances (beta)](https://create.roblox.com/docs/en-us/cloud/guides/instance), [Manage API keys](https://create.roblox.com/docs/en-us/cloud/open-cloud/api-keys)
- [Roblox/studio-rust-mcp-server](https://github.com/Roblox/studio-rust-mcp-server) (archived 2026-04-03), [boshyxd/robloxstudio-mcp](https://github.com/boshyxd/robloxstudio-mcp) (archived 2026-06-06), [Roblox/place-ci-cd-demo](https://github.com/Roblox/place-ci-cd-demo) (archived 2024-09-25)
- [Rojo project format](https://rojo.space/docs/v7/project-format/); Rojo v7.7.1 from the GitHub releases API
- [Security and cheat mitigation tactics](https://create.roblox.com/docs/en-us/scripting/security/security-tactics) and the [task library](https://create.roblox.com/docs/reference/engine/libraries/task) (the two habits the skill teaches; read through search summaries)
- [Roblox Terms of Use](https://en.help.roblox.com/hc/en-us/articles/115004647846-Roblox-Terms-of-Use): **not read**, since the page sits behind a Cloudflare check
