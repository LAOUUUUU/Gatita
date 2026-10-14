# 018: Web builds and WebGL (plan, not built)

**Status:** plan only. Written 2026-10-14, added after Lao asked about WebGL. Shared design and the order: [010](010-game-engines-overview.md). **Step 1** of 7, together with 017. The build-folder preview (route 1) is the one hard piece, so it comes last in this step. The web libraries themselves are in [017](017-web-engines-support-plan.md).

## What WebGL is, and why it gets its own plan

WebGL is not an engine. It is the browser's JavaScript API for drawing with the GPU on a `<canvas>`. **WebGL 2.0 is derived from OpenGL ES 3.0, and its shaders are written in GLSL ES 3.00** (Khronos spec, editor's draft of 2026-06-30). **WebGPU** is the newer browser API, with shaders in WGSL.

Three jobs use it, and they are different jobs:

| Job | Example | Where |
|---|---|---|
| Write WebGL or WebGPU code directly | a spinning cube in raw WebGL 2, a fragment shader | this plan |
| Use a web library on top of it | three.js, Babylon.js, PlayCanvas, Phaser | [017](017-web-engines-support-plan.md) |
| Export an engine's game to the web and run it | Unity Web, Godot Web, Bevy in WASM, Defold HTML5 | this plan (the export step is also noted in each engine's plan) |

So the web is a **build target for most engines in this set**, and WebGL is the layer under all of it.

## What the engines do on the web (checked 2026-10-14)

| Engine | Web target | Graphics API on the web | Things to know |
|---|---|---|---|
| **Unity** (Unity 6 manual, search summary) | Web platform | **WebGL 2 by default.** WebGPU must be switched on in Player settings and is experimental | Compression is gzip by default (Brotli is smaller). The server must send a matching `Content-Encoding`, and `.wasm` must be served as `application/wasm` |
| **Godot 4.7** (docs, read in full) | Web export | **WebGL 2.0 only,** through the Compatibility renderer. Forward+ and Mobile are not supported on the web, and WebGPU is not supported yet | Needs WebAssembly and WebGL 2.0. Chromium or Firefox recommended; Safari has WebGL 2.0 issues. Threads need `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`; the single-threaded export (the default since 4.3) needs neither. **C# projects can't export to the web.** The docs say to serve the exported folder |
| **Bevy** (the repo's examples README) | `wasm32-unknown-unknown` plus `wasm-bindgen` | **WebGL2 by default.** WebGPU is "experimental", behind a `webgpu` feature that overrides `webgl2` | The README serves the output with `python3 -m http.server --directory …` |
| **Defold** (bob manual) | `--platform wasm-web` ("HTML5") | not stated | A `wasm_pthread-web` architecture also exists |
| **GameMaker** | an HTML5 target in the IDE | not checked | `gm-cli`'s examples build an `operagx` package; its HTML5 output was not checked |
| **Unreal** | not checked | not checked | |

**Browser support for WebGPU** (web.dev, 2025-11-25): on by default in Chrome and Edge since version 113 (Windows with Direct3D 12, macOS, ChromeOS; Android from 121); Firefox on Windows from 141 and on macOS Tahoe 26 on Apple silicon from 145; Safari 26 on macOS Tahoe 26, iOS 26, iPadOS 26 and visionOS 26. Linux, Android Firefox and Intel Macs were still in progress. Unity and the web.dev-era guides both say to **keep WebGL 2 as the fallback**. I found no dated source for Safari's WebGL 2 support (unverified).

## Tested on this Mac (2026-10-14, macOS 27.0.1)

I loaded a page in a bare `WKWebView`, the same web engine Gatita's HTML preview uses, and asked it what it offers:

| Feature | With no origin (`baseURL: nil`) | With a secure origin (`https://…`) |
|---|---|---|
| WebGL 2 | **yes** ("WebGL 2.0", "WebGL GLSL ES 3.00") | yes |
| WebGL 1 | yes | yes |
| WebAssembly | yes | yes |
| WebGPU (`navigator.gpu`) | **no** | yes |
| Secure context | no | yes |
| Cross-origin isolated / `SharedArrayBuffer` | no / no | no / no |

Not tested: asking for a WebGPU adapter, actually drawing, or Gatita's own preview with its content rules and policy.

## What Gatita has today

- **`HTMLPreview`** (shown for `html` and `svg` code blocks; shared with iPhone and iPad) loads the page with `loadHTMLString(…, baseURL: nil)`, a non-persistent data store, a Content-Security-Policy of `default-src 'none'` with inline scripts allowed, and a rule that blocks every load. By the probe above, a **single-file WebGL 1 or 2 demo should already run there.** WebGPU would not (no secure origin), and any library loaded from a CDN would be blocked, so the model has to inline code or use raw WebGL.
- **No GLSL or WGSL coloring.** The tokenizer knows HTML and JavaScript but not shader languages.
- **No way to run a built web game.** A dev server can't listen inside the command sandbox (tested: `EPERM`), and the preview takes one string of HTML, not a folder.

## Routes

1. **Preview a built web folder inside Gatita, with no server.** A `WKURLSchemeHandler` for a custom scheme (say `gatita-game://`) would answer page requests from the chosen build folder. It needs no socket, so the sandbox rule does not matter, and the network stays blocked. The handler sets `Content-Type` (such as `application/wasm`) and `Content-Encoding` (`br` or `gzip` for Unity builds) for each file, reads read-only, and refuses anything outside the folder. **Unverified and to be tested first:** whether WebKit treats a custom scheme as a secure context (for WebGPU), whether COOP and COEP headers from the handler can give `crossOriginIsolated` (for threaded builds), and how `.wasm` streaming behaves under a custom scheme.
2. **Project files.** The page, the JavaScript or TypeScript, and shaders (`.glsl`, `.vert`, `.frag`, `.wgsl`) as text. The model needs the shader rules from the spec: GLSL ES 3.00 for WebGL 2 (the first line `#version 300 es`, which the Khronos page I read did not show, so it is to be confirmed from the spec when the skill is written).
3. **Commands.** `npm run build` already works. Engine exports need the sandbox decision in [010](010-game-engines-overview.md): Godot `--export-release "<preset>" <path>`, Unity's `unity build` for the Web target, Bevy `cargo build --release --target wasm32-unknown-unknown --offline` followed by `wasm-bindgen`. This Mac has the `wasm32-unknown-unknown` Rust target but **not** `wasm-bindgen` (a `cargo install`, which needs the network and compiles third-party code, so it is Lao's call).
4. **A real-browser check (later, only if wanted).** A headless Chromium run could capture console errors and a screenshot. It needs an install, a server and an unsandboxed run, so it is a Phase C item.

## Detection

A chip "WebGL" when a folder holds shader files or an `index.html` that asks for a `webgl2`, `webgl` or `webgpu` context; and "Web build" for an exported folder. The exact file names of each engine's export (the loader and `.wasm` names) must be taken from real exports in Phase B, not guessed.

## Coloring (new)

GLSL ES: C-like, with `vec2`/`vec3`/`vec4`, `mat3`/`mat4`, `sampler2D`, `uniform`, `in`/`out`, precision words, and `#version`/`#define` lines. WGSL: Rust-like, with `fn`, `var`, `struct`, `@vertex`, `@fragment` and `@group(0) @binding(0)`. Both keyword lists come from the Khronos and W3C specs when they are built, not from memory.

## Skill (`/webgl`)

WebGL 2.0 is OpenGL ES 3.0 with GLSL ES 3.00; check that `getContext` returned a context and fall back (WebGL 2, then WebGL 1, then a message); for WebGPU, feature-detect `navigator.gpu` and fall back to WebGL 2; WebGPU needs a secure context; the preview in Gatita runs scripts but cannot load anything from the network. For exports, the table above: Unity's compression headers, Godot's Compatibility renderer and no C#, Bevy's WebGL2 default. Drawing details come from MDN and the specs when it is written.

## Milestones (each starts with a failing test)

*Phase A: needs no engine.*
1. GLSL and WGSL coloring.
2. A real-WebKit test, like the existing preview tests, that Gatita's own preview can create a WebGL 2 context. It settles what the preview can and cannot do before anything else is built on it.
3. The `/webgl` skill and the shader-file markers for `GameProject`.
4. The build-folder preview (route 1) with a fixture folder: it serves `index.html`; serves `.wasm` as `application/wasm`; adds `Content-Encoding` for `.br` and `.gz` files; refuses `..` and paths outside the folder; and cannot reach the network.

*Phase B: needs a web export.*
5. A Godot Web export (single-threaded), a Bevy WASM build (after `wasm-bindgen` is installed), and a Unity Web build. Run each through the handler, record the real file names, and test a threaded build and a WebGPU build.

*Phase C: only on a yes.* A headless browser check; publishing a build anywhere.

## Limits and risks

- The preview is WebKit. A game that runs there can still fail in Chrome, and the reverse (Godot's docs say Safari has WebGL 2.0 issues). Real-browser testing stays with the user.
- Threaded WASM needs cross-origin isolation, which the bare `WKWebView` did not have.
- Unity's Brotli builds are large. The handler must stream files, not read them whole into memory.
- A scheme handler that serves a project folder to a web page is a security surface: read-only, one chosen folder, no path escape, no shared storage or cookies with Gatita, and no network. It gets its own tests and a review before it ships.
- WebGPU is moving: experimental in Unity and Bevy, and not available in Godot's web export yet.

## Decisions needed

1. Should games run **inside Gatita** (the build-folder preview), or is "run it in your browser" enough? Inside Gatita is more work and adds a security surface; the browser needs only the files route.
2. Which web exports matter to you: Unity Web, Godot Web, Bevy WASM, Defold HTML5?
3. WebGL 2 first, with WebGPU as a later opt-in? (I suggest yes: WebGL 2 is every engine's default.)
4. Is installing `wasm-bindgen-cli` OK when we get to the Bevy web build?

## Sources

- [WebGL 2.0 specification (Khronos editor's draft, 2026-06-30)](https://registry.khronos.org/webgl/specs/latest/2.0/): derived from OpenGL ES 3.0, GLSL ES 3.00
- [Godot: Exporting for the Web (4.7 docs)](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Unity 6 manual: WebGL deployment](https://docs.unity3d.com/Manual/webgl-deploying.html) and [WebGPU on the web](https://docs.unity3d.com/Manual/WebGPU-enable.html) (read through a search summary)
- [Bevy examples README, WebAssembly section](https://github.com/bevyengine/bevy/blob/main/examples/README.md) (read from the repo with the GitHub API)
- [Defold manual: Bob the builder](https://defold.com/manuals/bob/) (platforms and architectures)
- [WebGPU is now supported in major browsers (web.dev, 2025-11-25)](https://web.dev/blog/webgpu-supported-major-browsers)
- The WebKit probe and the sandbox replay: run on this Mac on 2026-10-14. The probe's code is in the session scratchpad, not the repo.
- `rustup target list --installed` and `command -v wasm-bindgen` on this Mac
