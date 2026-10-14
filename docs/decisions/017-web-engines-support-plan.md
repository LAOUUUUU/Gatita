# 017: Web engines support (plan, not built)

**Status:** plan only. Written 2026-10-14. Shared design and the order: [010](010-game-engines-overview.md). **Step 1** of 7, the easiest of all: it can be tried for real on this Mac today.

## Goal

On the Mac, Gatita Code writes and checks a browser game made with Phaser, three.js, Babylon.js or PlayCanvas, and drives a PlayCanvas Editor session through its official MCP server.

## The engines in short

All four are JavaScript or TypeScript that run in the browser, and they draw through WebGL (and, increasingly, WebGPU). WebGL itself, raw shader work, and showing a built web game inside Gatita are covered in [018](018-web-builds-and-webgl-plan.md). Versions and sizes from the GitHub API on 2026-10-14:

| Engine | What it is | Latest | Stars | License |
|---|---|---|---|---|
| Phaser | 2D game framework | v4.2.1 (2026-07-09) | 40,477 | MIT |
| three.js | 3D library | r186 (2026-09-24) | 116,408 | MIT |
| Babylon.js | 3D engine | 9.30.0 (2026-10-08) | 26,164 | Apache-2.0 |
| PlayCanvas | engine plus an online editor | v2.23.2 (2026-10-09) | 17,037 | MIT |

- **Why they fit this Mac:** node v24.19.0 and npm 11.17.0 are installed, `npm test` and `npm run build` are already allowed commands, and I tested that `npm run build` works inside Gatita's sandbox.
- **What does not fit:** a dev server (`npm run dev`, `vite`) must listen on a port, and I tested that a program cannot listen on localhost inside the sandbox (`EPERM`). The user runs the dev server in a terminal; Gatita edits the files.

## What exists for AI tools today (2026-10-14)

- **PlayCanvas Editor MCP server (official).** Package `@playcanvas/editor-mcp-server` (v0.7.1, 2026-09-09, MIT, 143★, so still pre-1.0). From PlayCanvas's docs:
  - It needs Node.js 22.18 or later (this Mac has 24.19.0) and runs through `npx -y @playcanvas/editor-mcp-server`.
  - The MCP client starts it. The Editor, open in a Chromium browser, then connects to it: click **MCP** in the Editor toolbar, confirm port `52000` (change it with `--port`), and Connect. Only one Editor instance can connect at a time. Chrome 142+ asks for local-network access, and a blocked connection fails silently.
  - Tools cover entities, components, scripts, assets, scenes, project settings, templates, animation, builds and version control, plus viewport capture, launching and capturing the running app, runtime logs, and injected keyboard, mouse and touch input.
  - It changes the project directly (there is no local push step) and **can delete entities, assets, builds and branches, and reset the project**. The docs advise a checkpoint before big changes.
- **three.js:** no official MCP server found. **Phaser and Babylon.js:** I did not verify any MCP server.

## Routes

1. **Editor tools: the PlayCanvas server as a stdio entry in `MCPHub`** (Mac, Debug build; it is not inside the command sandbox, so listening on port 52000 is fine). Pin the version in the preset (`@playcanvas/editor-mcp-server@0.7.1`), never `@latest`. Each call asks first, and this server is never Trusted: it can delete things.
2. **Project files.** The game's JavaScript or TypeScript, `package.json`, and assets. This is the whole route for Phaser, three.js and Babylon.js.
3. **Commands.** `npm test` and `npm run build` already work. Candidates to add: `npm run lint` and `npm run typecheck` (they run the project's own scripts, so they need the same care as `npm test`). `npx` fetches packages from the network, so it can't be an allowed entry.

## Detection

A `package.json` whose dependencies include `phaser`, `three`, `@babylonjs/core` or `babylonjs`, or `playcanvas`. The chip names the library and its version ("Phaser 4.2"). The Roblox detector only looks at file names; this one also reads JSON.

## Skill (`/webgame`)

Browser limits (no file system, assets load by URL), the frame loop, using the project's own package manager and scripts, "the dev server is run by the user", and library-version cautions: Phaser 3 and Phaser 4 differ, so check `package.json` first. Library details come from each project's docs when the skill is built.

## Milestones (each starts with a failing test)

*Phase A: testable today.*
1. `package.json` detection, the chip, and the `/webgame` skill. JavaScript and TypeScript coloring exists.
2. Allowed entries for `npm run lint` and `npm run typecheck`, if Lao agrees.
3. A "PlayCanvas Editor" preset (pinned `npx`, port note, "keep the client running" and "allow local network access" messages), tested against the stdio mock.

*Phase B: needs a PlayCanvas account and Chrome.*
4. A live run: connect the Editor, record the real tool list, update the mock.

*Phase C: only on a yes.* Anything that publishes a build.

## Limits and risks

- `npx -y` runs whatever the package is. Pin it. The community Roblox server that was archived after its owner lost their npm keys is the cautionary example.
- A blocked local-network prompt fails silently, so the preset's messages matter.
- Destructive tools in the PlayCanvas server; a checkpoint before any large change.
- The Editor must stay open in a browser tab while the server runs.

## Decisions needed

- Which of these do you want to use? Phaser (2D) and three.js (3D) need no account at all.
- Add `npm run lint` and `npm run typecheck` to the allowed commands?

## Sources

- [PlayCanvas Editor MCP server docs](https://developer.playcanvas.com/user-manual/editor/mcp-server/) (read 2026-10-14)
- GitHub API, 2026-10-14: phaserjs/phaser, mrdoob/three.js, BabylonJS/Babylon.js, playcanvas/engine, playcanvas/editor-mcp-server
- The sandbox replay (`npm run build` works, listening fails): [010](010-game-engines-overview.md)
- Versions of node and npm: `node -v`, `npm -v` on this Mac
