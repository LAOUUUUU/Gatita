# 015: Bevy support (plan, not built)

**Status:** plan only. Written 2026-10-14. Shared design and the order: [010](010-game-engines-overview.md). **Step 2** of 7, the easiest engine to support, since it can be tried for real on this Mac today.

## Goal

On the Mac, Gatita Code writes and checks a Bevy game's Rust code, and, if wanted, inspects and changes the running game through Bevy's remote protocol.

## Bevy in short

- A Rust game engine built on an entity-component-system (ECS). Latest release **v0.20.0** (2026-10-08). 48,997★, Apache-2.0 on GitHub. There is no editor: a Bevy game is a Rust program.
- **Why it fits this Mac:** `cargo` and `rustc` are installed, and Lao already writes Rust. No download or sign-in is needed to start.
- No reliable usage share found (see [010](010-game-engines-overview.md)).

## What exists for AI tools today (2026-10-14)

- No official MCP server. Bevy has the **Bevy Remote Protocol (BRP)**: add `bevy::remote::RemotePlugin` to a game and tools can query and change its ECS world while it runs. The usual port in the tools' examples is 15702.
- **`bevy_brp_mcp`** (natepiano/bevy_brp, v0.23.0 on 2026-10-09, MIT or Apache-2.0, 75★) is an MCP server for AI coding assistants. Install: `cargo install bevy_brp_mcp`. From its README it can find and run Bevy examples, launch and stop apps, query entities (`world.query`), run BRP methods (`brp_execute`, which first checks `rpc.discover`), and list tools a game registers. An optional `bevy_brp_extras` plugin (`BrpExtrasPlugin`) adds methods and screenshots (`brp_extras_screenshot`). Its README describes Bevy 0.20 behavior.
- A security note, since the pages I read don't give one: BRP is remote control of a running game. Use it in debug builds only, and check its default listening address in the Bevy docs before relying on "localhost only" (unverified).

## Routes

1. **Editor tools: BRP through `bevy_brp_mcp`,** a stdio server in `MCPHub` (Mac, Debug build). The game must be running **outside** the command sandbox: BRP listens on a local port, and I tested that a program cannot listen on localhost inside the sandbox (`EPERM`). So the user starts the game with `cargo run` in a terminal, and Gatita connects to it. Gatita's own `run_background` cannot host it.
2. **Project files.** Rust sources, `Cargo.toml`, and the `assets/` folder. All text except the assets.
3. **Commands: this is where Bevy is strongest.** Tested on this Mac on 2026-10-14 with Gatita's sandbox rules: `cargo build` of a crate with no dependencies works, and with a registry dependency `cargo build --offline` works when the crate is already cached. Plain `cargo build` fails (no network). So allowed entries would be `cargo check --offline`, `cargo build --offline`, `cargo test --offline`, `cargo clippy --offline` (clippy 0.1.98 is installed here) and `cargo fmt --check` (rustfmt 1.9.0 is installed here). The first fetch of a game's dependencies needs the network, so the user runs `cargo fetch` once in a terminal. `cargo` is not in the built-in allowed commands today.

**Web target.** Bevy builds for the browser with the `wasm32-unknown-unknown` target plus `wasm-bindgen`, on WebGL2 by default (an experimental `webgpu` feature exists). This Mac has the Rust target but not `wasm-bindgen`. Details: [018](018-web-builds-and-webgl-plan.md).

## Detection

A `Cargo.toml` that lists `bevy` as a dependency, read as text. The chip shows the Bevy version ("Bevy 0.20"). An engine's own file beats a generic one, so a Godot project that also has a `Cargo.toml` stays a Godot project ([010](010-game-engines-overview.md)).

## Skill (`/bevy`)

ECS in plain words (components, systems, resources, plugins); a short loop of `cargo check --offline` after edits; and the most important rule: **Bevy's API changes with almost every 0.x release,** so the model reads the version in `Cargo.toml`, trusts the compiler's messages and the docs for that version over its memory, and never guesses names. Coloring for Rust already exists.

## Milestones (each starts with a failing test)

*Phase A: testable today.*
1. The Bevy marker for `GameProject`, the chip, and the `/bevy` skill.
2. Allowed entries for the `cargo … --offline` commands: a policy test with a fixture crate (it needs no Bevy). Whether they are built in or a plugin is a decision.
3. A "Bevy (BRP)" preset with plain messages ("`bevy_brp_mcp` not installed", "game not running"), tested against the stdio mock.

*Phase B: needs a Bevy project.*
4. A tiny Bevy project, `cargo fetch` once by the user, then a real `cargo check --offline` through the sandbox profile.
5. `cargo install bevy_brp_mcp` (compiles third-party code on this Mac, so it is the user's call), then a live check against a running game.

*Phase C: only on a yes.* Release builds and packaging.

## Limits and risks

- API churn: a fresh `Cargo.toml` can pin a different Bevy than the one the model remembers.
- The first build compiles a large dependency tree and is slow.
- `--offline` needs a warm cache. A new project fails until its dependencies are fetched outside the sandbox.
- BRP changes a live game with no authentication that I could confirm. Debug builds only.
- `bevy_brp_mcp` is community code. Pin the version and never mark it Trusted.

## Decisions needed

- Add `cargo … --offline` to the built-in allowed commands, or ship it as a plugin?
- Is a small Bevy project on your Mac OK as the test bed?

## Sources

- GitHub API, 2026-10-14: bevyengine/bevy (v0.20.0, 48,997★, Apache-2.0), natepiano/bevy_brp (v0.23.0, 75★)
- [natepiano/bevy_brp](https://github.com/natepiano/bevy_brp) and its `mcp/README.md` (install, tools, `RemotePlugin`, `BrpExtrasPlugin`, port 15702 in the examples), read 2026-10-14
- The sandbox replay of `cargo` on this Mac: [010](010-game-engines-overview.md)
