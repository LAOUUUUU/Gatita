# 009: Gatita's first Swift packages

**Date:** 2026-10-13
**Status:** Accepted

## Context

Until now Gatita had no package dependencies: code colors, charts, and the connectors were written in the app. Lao asked for math and diagrams in replies, and for MCP servers. Both are large, specialised jobs that well-kept packages already do. The research is in [research/feature-batch-2026-10](../../research/feature-batch-2026-10/RESEARCH.md), and Lao approved the three packages there.

## Decision

- **Math: [LaTeXSwiftUI](https://github.com/colinc86/LaTeXSwiftUI) 2.x (MIT).**
  - It is a SwiftUI view for text that mixes words and `$…$` math, which is how models write it.
  - It renders with MathJax in JavaScriptCore (through MathJaxSwift), off the main thread.
  - It shows the plain text until the math is ready (`renderingStyle(.original)`).
  - SwiftMath was the other choice: native, but only a label, with no mixed text and math.
- **Diagrams: [BeautifulMermaid](https://github.com/lukilabs/beautiful-mermaid-swift) 1.x (MIT).**
  - It draws Mermaid natively, with no web view: flowchart, state, sequence, class, ER, and XY charts.
  - Bundling `mermaid.js` in a `WKWebView` would cover more diagram types, but at the cost of a web view per diagram.
- **SVG: [SwiftDraw](https://github.com/swhitty/SwiftDraw) 0.29.x (zlib), added 2026-10-14.**
  - It was already in the app as LaTeXSwiftUI's dependency; Gatita now depends on it directly, pinned to the 0.29 minor line, so the resolved version did not change.
  - It turns SVG into native drawing commands, so `svg` blocks show as pictures on iPhone and iPad, where `UIImage(data:)` can't read SVG, and the same way on the Mac.
  - It loads nothing from the network. The other choice was a locked-down `WKWebView` per picture: complete SVG support, but heavier and harder to size in a chat.
- **MCP: the official [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) 0.12.x.**
  - It targets the 2025-11-25 spec, with a `Client`, `StdioTransport` (over file descriptors, so Gatita starts local servers itself), and `HTTPClientTransport`.
  - It is pinned to the 0.12 minor line, since a release before 1.0 can change its API.
  - It also brings swift-log, swift-system, EventSource, and (for its own example targets) swift-nio.

Versions follow "up to the next major" from the version researched, and `Package.resolved` pins what was built.

## Consequences

- The first build fetches the packages. Their transitive dependencies are MathJaxSwift, SwiftDraw, swift-html-entities, elk-swift, swift-log, swift-system, swift-atomics, swift-collections, swift-nio, and EventSource.
- Only paragraphs that hold math (`MathDetection`) and `mermaid`, `math`, `latex`, or `svg` blocks use the packages, so ordinary replies draw as fast as before.
- `MermaidBlockView` waits for a streaming diagram to stop changing before it draws, and falls back to the code block.
- Adding the packages changed the app's launcher binary. macOS then asked once more for Keychain access to the saved API key, which also froze the test host. The app the tests run in no longer touches the Keychain (`ChatViewModel.isTesting`).
