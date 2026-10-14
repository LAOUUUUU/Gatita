# Research: Gatita feature batch (12 features)
**Date:** 2026-10-13
**Status:** Complete, waiting for approval
**Researcher:** Claude Code

## Question
How should Gatita add the 12 features Lao picked, and which of them need a new dependency, a change to saved data, or a change to what Gatita is allowed to do?

1. Find in chats (⌘F in a chat, and the sidebar search looking inside messages)
2. Memory across chats
3. Math (LaTeX) and diagrams (Mermaid) drawn in replies
4. PDF attachments
5. Scheduled prompts ("nightly tasks") with notifications
6. Shortcuts and Siri
7. "Ask Gatita" on selected text in any Mac app (Services menu)
8. HTML and SVG preview of code blocks
9. Checkpoints: undo a reply's file changes
10. Ask before running commands
11. MCP servers
12. Pinned chats and folders

## Context
Gatita is one SwiftUI app (macOS 26.6+, iOS 27+), Swift 6.4 compiler in Swift 5 mode, default MainActor isolation, no Swift packages today. The Mac is the full host; iPhone and iPad answer questions only ([001](../../docs/decisions/001-question-only-hosts.md)). Tools use the text protocol `<gatita-tool>{json}</gatita-tool>`.

## Findings

### Internal
- **No dependencies yet.** The highlighter, charts, and connectors were all written without packages. Your rules say to ask before adding one.
- **Chats** are one `chats.json` of `Conversation` (`id`, `updatedAt`, `messages`, `customTitle?`, `mode?`). Optional fields load from older files, which is how `mode` was added.
- **Sidebar search** matches titles only (`HostChatView.swift:336`).
- **Commands:** one on/off switch (`allowCommands`), a fixed allow list, no shell, and a sandbox profile with no network ([architecture](../../docs/architecture.md#safety)). Commands run inside `ProjectTools.execute`, which is `@concurrent` (off the main actor).
- **File changes:** `ProjectTools.changePreview` already works out a diff before `write_file` and `edit_file` run, and the reply records it (`fileChanged` events). That is the hook checkpoints need.
- **Sandbox:** the Debug build you run has App Sandbox off; the Release build has it on. A sandboxed app can't start arbitrary programs such as `npx`, which matters for MCP.
- **Notifications** (`ReplyNotifier`) and the menu bar item (shown while long tasks run) already exist, which scheduled prompts can reuse.
- **The quick panel** already exists, so "Ask Gatita" from the Services menu can open it with the text.

### External
- **Find:** SwiftUI's `findNavigator(isPresented:)` only works with a `TextEditor`, not a transcript of custom views, so Gatita needs its own find bar.
- **Memory:**
  - Anthropic's memory tool is client-side: the model asks to view, create, edit, or delete memory files, and the app runs each request against storage it controls.
  - The docs stress three things: block path traversal, cap file sizes, and expire old memories.
  - The reference MCP memory server keeps short "observations" about the user in one local JSONL file.
- **Math:**
  - LaTeXSwiftUI (v2, Swift 6, iOS 15+/macOS 12+) is a SwiftUI view for text with inline `$…$` and block `$$…$$` math. It runs MathJax in JavaScriptCore (through MathJaxSwift), renders off the main thread, and caches results.
  - SwiftMath (MIT) is native with no JavaScript, but it is an AppKit/UIKit label you wrap yourself, and it has no mixed text-and-math view.
- **Diagrams:**
  - BeautifulMermaidSwift 1.0.4 (27 Apr 2026, MIT, iOS 15+/macOS 12+) draws Mermaid natively, with no WebView. It covers flowchart, state, sequence, class, ER, and XY charts. It depends on ElkSwift.
  - The alternative is bundling `mermaid.js` in a `WKWebView`, which covers all of Mermaid's syntax but costs a web view per diagram.
- **PDF:** PDFKit's `PDFDocument.string` returns the whole document's text, with pages separated by line feeds, on iOS 11+ and macOS 10.4+.
- **Scheduling:**
  - `NSBackgroundActivityScheduler` (macOS only) lets the system pick the time within a window, aimed at deferrable work every 10 minutes or more. It can't promise "at 8:00".
  - `SMAppService.mainApp` (macOS 13+) registers Gatita as a login item, subject to your approval in System Settings.
  - ChatGPT's scheduled tasks (relaunched June 2026) offer a time or a morning/afternoon/evening window, at most once an hour, a sidebar page to pause, edit, or delete tasks, and a notification when a task has something.
- **Shortcuts and Siri:**
  - `AppIntent` and `AppShortcutsProvider` are on iOS 16+ and macOS 13+.
  - An intent's `perform()` is `async throws` and returns a result. Each App Shortcut phrase includes the app's name.
  - At WWDC 2026 Apple deprecated SiriKit, so App Intents is the only way for Siri to reach an app (sessions 344 and 345).
- **Services menu:**
  - An app lists its services in `NSServices` in Info.plist (`NSMessage`, `NSPortName`, `NSSendTypes`, `NSMenuItem`).
  - It sets one `NSApp.servicesProvider`, whose handler has the form `name(_ pasteboard:userData:error:)`.
  - The app must be in /Applications. `NSUpdateDynamicServices()` makes the service appear without logging out.
- **HTML preview:**
  - `WKWebpagePreferences.allowsContentJavaScript` turns scripts off.
  - A `WKContentRuleListStore` rule list, added to the web view's `WKUserContentController`, blocks loads by URL. A catch-all block rule plus a non-persistent data store keeps a preview from reaching the network.
- **Checkpoints:**
  - Claude Code snapshots the files its edit tools change before each prompt. It can restore code, the conversation, or both, and it does not track changes made by shell commands.
  - Cline commits the whole project to a shadow git repository after each tool use, and offers Restore Files, Restore Task, or both.
- **Ask before commands:**
  - Claude Code asks for each Bash command. "Yes, and don't ask again" saves a prefix rule per repository, such as `npm test *`.
  - Its rules are checked deny, then ask, then allow, and each part of a compound command must match.
  - Codex CLI's `/permissions` chooses when it may edit files or run commands without asking.
- **MCP:**
  - The official swift-sdk is at 0.12.1 (7 May 2026; 0.11.0 added the 2025-11-25 spec). It needs Swift 6.0+, macOS 13+, iOS 16+.
  - It has `StdioTransport(input:output:)`, which takes file descriptors and does not start the server itself, and `HTTPClientTransport(endpoint:streaming:)` for remote servers.
  - A community SDK notes that stdio servers in a Mac app need the sandbox off, since the app starts a process per server.

## Sources
| Source | URL | Key takeaway |
|---|---|---|
| SwiftUI `findNavigator` | https://developer.apple.com/tutorials/data/documentation/swiftui/view/findnavigator(ispresented:).md | Find bar only for `TextEditor`, so a custom find is needed |
| Anthropic memory tool | https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool | Client-side memory; path traversal, size caps, expiry |
| MCP reference memory server | https://github.com/modelcontextprotocol/servers/tree/main/src/memory | Facts ("observations") about the user in one local file |
| LaTeXSwiftUI | https://github.com/colinc86/LaTeXSwiftUI | SwiftUI text with inline and block math, off-main rendering, caches |
| MathJaxSwift | https://github.com/colinc86/MathJaxSwift | MathJax bundled, run in JavaScriptCore; keep one instance off main |
| SwiftMath | https://github.com/mgriebling/SwiftMath | Native, no JS, MIT; label only, no mixed text |
| BeautifulMermaidSwift | https://swiftpackageregistry.com/lukilabs/beautiful-mermaid-swift | Native Mermaid, 6 diagram types, 1.0.4, MIT, depends on ElkSwift |
| PDFKit `PDFDocument.string` | https://developer.apple.com/tutorials/data/documentation/pdfkit/pdfdocument/string.md | Whole-document text, iOS and macOS |
| NSBackgroundActivityScheduler | https://developer.apple.com/tutorials/data/documentation/foundation/nsbackgroundactivityscheduler.md | System-chosen times, deferrable; not for exact times |
| SMAppService | https://developer.apple.com/tutorials/data/documentation/servicemanagement/smappservice.md | `mainApp` login item, needs user approval |
| ChatGPT scheduled tasks (9to5Mac, June 2026) | https://9to5mac.com/2026/06/17/openai-launches-scheduled-tasks-in-chatgpt-details-here/ | Times or windows, a Scheduled page, at most hourly |
| AppIntent | https://developer.apple.com/tutorials/data/documentation/appintents/appintent.md | `perform() async throws`, background or foreground modes |
| AppShortcutsProvider | https://developer.apple.com/tutorials/data/documentation/appintents/appshortcutsprovider.md | iOS 16+, macOS 13+ |
| WWDC26 notes (Bitrise) | https://bitrise.io/blog/post/wwdc26-under-the-radar | SiriKit deprecated; App Intents is the way into Siri |
| Services (Apple archive) | https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html | Info.plist keys, one provider, `NSUpdateDynamicServices`, /Applications |
| Services (Nil Coalescing) | https://nilcoalescing.com/blog/macOSSystemWideServices | A worked example with the Swift handler signature |
| `allowsContentJavaScript` | https://developer.apple.com/tutorials/data/documentation/webkit/wkwebpagepreferences/allowscontentjavascript.md | Turns off all scripts in a web view |
| WKContentRuleListStore | https://developer.apple.com/tutorials/data/documentation/webkit/wkcontentruleliststore.md | Compile JSON block rules, add them to the content controller |
| Claude Code checkpointing | https://code.claude.com/docs/en/checkpointing | File snapshots per prompt; shell changes not tracked |
| Cline checkpoints | https://docs.cline.bot/features/checkpoints | Shadow git repository; restore files, task, or both |
| Claude Code permissions | https://code.claude.com/docs/en/permissions | Ask per command; "don't ask again" saves a prefix rule per repo |
| Codex CLI | https://learn.chatgpt.com/docs/codex/cli | `/permissions` decides when commands run without asking |
| MCP swift-sdk | https://github.com/modelcontextprotocol/swift-sdk | Swift 6, macOS 13+/iOS 16+, spec 2025-11-25, stdio and HTTP clients |
| swift-sdk `StdioTransport` | https://github.com/modelcontextprotocol/swift-sdk/blob/main/Sources/MCP/Base/Transports/StdioTransport.swift | Wraps file descriptors; does not start the server |
| swift-sdk releases | https://github.com/modelcontextprotocol/swift-sdk/releases | 0.12.1 (7 May 2026), 0.12.0, 0.11.0 |

## Recommendation
Build them one at a time, smallest and safest first, with tests first and the full suite after each. In order:

1. **Pinned + folders.**
   - `Conversation` gets `pinned: Bool?` and `folder: String?`. Both are optional, so old `chats.json` files still load. *Change to saved data.*
   - The sidebar shows Pinned first, then each folder (collapsible), then the rest.
   - Right-click a chat for Pin or Unpin, and Move to Folder (existing folders, New Folder…, or none).
2. **Find in chats.**
   - `ChatSearch` (pure, tested) finds a query in every message and returns a snippet. The sidebar shows matching chats with that snippet.
   - ⌘F opens a find bar over the chat, with the match count and ⌘G / ⇧⌘G for next and previous. It scrolls to each match and highlights it in the reply text.
3. **PDF attachments.**
   - A dropped PDF becomes text through PDFKit, with its page count, capped like other files.
   - A PDF with no text (a scan) says so, rather than sending nothing.
4. **Memory.**
   - Tools `remember` (one short fact), `forget`, and `list_memories`, on every host and in both modes.
   - Memories are kept in `memory.json`, at most 100 facts of 300 characters each. They are added to every reply's instructions under "What you know about the user".
   - Settings → Memory lists them, with delete, add, "forget everything", and an on/off switch.
   - A fact that looks like a password or key is refused (the same patterns as `SafetyFlags`).
5. **Ask before commands.**
   - `allowCommands` stays as the master switch. A new setting, "Ask before each command", is on by default.
   - Before `run_command` or `run_background`, the client awaits your answer in a Gatita dialog: Allow once, Always allow `<command prefix>` in this project, or Deny.
   - "Always" rules are saved per project folder in settings.json. *Change to saved data, and to what Gatita may do.*
   - A denied command returns "error: the user denied this command" to the model.
6. **Checkpoints.**
   - Before each `write_file` or `edit_file` in a reply, the file's earlier content (or "did not exist") is saved under `Application Support/Gatita/checkpoints/<reply id>.json`.
   - A finished Code reply that changed files gets "Undo changes". It restores every file to its state before the reply. If a file changed again since, it asks first.
   - As in Claude Code, changes made by commands are not tracked, and the button's help says so.
   - Checkpoints older than 30 days are deleted.
7. **HTML/SVG preview.**
   - An `html` or `svg` code block gets a Preview button that opens a panel with a `WKWebView`.
   - The panel uses a non-persistent data store and a content rule list that blocks every network load. Scripts are allowed, since many previews need them, and there is no bridge to Gatita.
   - Mac and iPad.
8. **Services: "Ask Gatita".**
   - `NSServices` in Info.plist plus `NSApp.servicesProvider`. Selected text opens the quick panel with that text attached as context, and you type the question.
   - `NSUpdateDynamicServices()` runs at launch, so the service appears without logging out.
9. **Shortcuts + Siri.**
   - An "Ask Gatita" `AppIntent` (question in, answer out, with a spoken dialog), using the quick panel's Chat-mode client.
   - Also "Start a New Chat" and "Open the Quick Panel" (Mac).
   - An `AppShortcutsProvider` with phrases such as "Ask Gatita". Mac and iPhone/iPad.
10. **Scheduled prompts.**
    - Mac only, while Gatita is running (the menu bar item keeps it reachable with the window closed). iOS can't promise a time.
    - A Scheduled page in Settings: a prompt, Chat or Code, and when: daily at a time, weekdays, weekly, or hourly. Saved in `schedules.json`.
    - A one-minute timer checks for due runs. `NSBackgroundActivityScheduler` can't hit "8:00".
    - A run missed while the Mac slept runs once on wake, within 12 hours.
    - Each run saves a chat in a "Scheduled" folder (from step 1) and always sends a notification.
    - Optional "Open Gatita at login" (`SMAppService.mainApp`). *System login item, off by default.*
11. **Math + diagrams.** *Two new dependencies.*
    - LaTeXSwiftUI for paragraphs that contain math. Gatita's own check decides what counts as math, so "$5 and $10" stays text.
    - BeautifulMermaidSwift for `mermaid` blocks. A diagram type it can't draw stays a code block.
    - Both stay out of everything else, so ordinary replies draw as fast as now.
12. **MCP servers.** *New dependency: the official swift-sdk 0.12.x.*
    - Settings → MCP Servers: add a local server (command, arguments, environment) or a remote one (URL), with the same shape as Claude Desktop's `mcpServers`. Saved in `mcp.json`.
    - Local servers are started with `Process` and pipes handed to `StdioTransport`. Remote servers use `HTTPClientTransport`.
    - Their tools reach the model as `mcp__<server>__<tool>` in the tool instructions. Every MCP call goes through the step-5 approval unless you mark the server trusted.
    - Remote servers work on every device. Local servers need the Mac with App Sandbox off (the Debug build you use); the Release build says local servers are unavailable.

## Test plan sketch
- [ ] `ConversationTests`: a chats.json without `pinned`/`folder` loads; pin and folder survive save and load; the sidebar order is pinned, folders, then the rest.
- [ ] `ChatSearchTests`: case-insensitive matches across messages, snippets around the match, no match in error or notice messages; `FindInChat` counts occurrences and steps next/previous with wraparound.
- [ ] `PDFAttachmentTests`: a generated PDF's text and page count come back; a PDF with no text says so; the size cap applies.
- [ ] `MemoryTests`: remember/forget/list; the 100-fact and 300-character caps; a secret-looking fact is refused; the instruction block lists facts; memory off sends none.
- [ ] `CommandApprovalTests`: a prefix rule matches `swift test --filter X` but not `swift build`; "always" is per project; a denied call returns the denial; with ask off, nothing asks.
- [ ] `CheckpointTests`: the earlier content is saved before a write and an edit; undo restores both and removes a file the reply created; a file changed since is reported, not overwritten.
- [ ] `HTMLPreviewTests`: the block rule list JSON blocks everything; html/svg blocks are previewable and others are not.
- [ ] `ServicesTests`: the Info.plist service entry is present; the handler turns pasteboard text into quick-panel context.
- [ ] `ScheduleTests`: next run times for daily, weekdays, weekly, and hourly, across DST and midnight; a missed run within 12 hours runs once on wake, older ones are skipped.
- [ ] `IntentTests`: the Ask Gatita intent with no key fails with a message; with the mock server it returns the answer.
- [ ] `MathDetectionTests`: `$x^2$`, `\(a\)`, `$$…$$` count as math; "$5 and $10" and code spans do not.
- [ ] `MCPConfigTests`: mcp.json in Claude Desktop's shape loads; tool names are prefixed; with the mock MCP server (stdio, a Python script), list and call a tool.

## Risks & unknowns
- **Dependencies:** three new packages and their own dependencies: MathJaxSwift (bundles MathJax, adding a few MB), ElkSwift, and the swift-sdk's dependencies.
  - The swift-sdk is pre-1.0, so its API can change between minor versions.
  - I have not checked how each builds with Swift 6.4 in Swift 5 mode with default MainActor isolation. Verify by building before relying on them.
- **App Intents with default MainActor isolation:** `AppIntent` is `Sendable`. An intent type isolated to the main actor may need `nonisolated` members. Check with a build first.
  - Siri may give up on a reply that takes long; the answer would then still be in Gatita.
- **Services:** they appear only for an app in /Applications (where you install Gatita). Ad-hoc signing should not matter, but it is not checked.
- **MCP:** local servers start programs outside the command sandbox, with network access. That is the point of MCP, but it is a real trust step, so each server is added by you and its calls ask before running.
  - Many MCP tools also make the instructions longer, so tools of servers that are off are left out.
- **Scheduled prompts:** nothing runs while Gatita is quit or the Mac is asleep. Catch-up on wake covers sleep; login launch covers restarts.
- **Memory:** the model decides what to remember, so it may save too much or too little. The Settings page and the caps keep it in check.
- **Math detection:** dollar signs in prices are the main false positive. The custom check is tested, but models vary.
- **Size of the batch:** this is several days of work. I'd checkpoint after each feature with the full suite, docs, and the handoff, so you can stop or reorder at any point.

## Next steps
- [ ] Lao approves, or changes the order or scope.
- [ ] Approvals needed:
  - the three dependencies (LaTeXSwiftUI, BeautifulMermaidSwift, MCP swift-sdk)
  - the chat file fields (`pinned`, `folder`)
  - the new settings and files (`memory.json`, `schedules.json`, `mcp.json`, command rules, checkpoints)
  - the command-approval change
  - the optional login item
- [ ] Then `specs/<feature>.md` for the larger ones (checkpoints, command approval, scheduled prompts, MCP), and `/tdd-cycle` feature by feature in the order above.
