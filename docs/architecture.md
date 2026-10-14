# Architecture

Gatita is one SwiftUI app with several targets. The Mac is the full host. iPhone, iPad, and Vision Pro are hosts that answer questions. See [ROADMAP.md](../ROADMAP.md) for the platform roles and the plan.

## Folders

| Folder | What is in it |
|---|---|
| `App/` | The app entry point (`GatitaApp.swift`) and the asset catalog (icons, logo, menu bar icon). |
| `Shared/` | Code for every platform that builds it: networking, tools, connectors, models, view model, views, shop, settings, chat history, logging, safety rules, and the task registry (`Shared/Tasks`). |
| `macOS/` | Code that only makes sense on the Mac: the sandboxed command runner and background process, the web check, the GitHub and Calendar connectors, the git process runner, the menu bar, the file tree, the pull-request sheet, the mode switch, the activity panel, the sleep guard, the quick panel and Services, the local MCP server process (`MCPProcess`), the launch work (`MacLaunch`), the chat window's layout and toolbar (`MacChatLayout`), and the Project, Quick panel, and Scheduled settings pages. |
| `iOS/` | Code for iPhone and iPad: the iPhone's link to the Apple Watch app (`HostSession+Watch`, `#if os(iOS)`) and the chat layout for touch screens (`TouchChatLayout`, `#if !os(macOS)`, which Vision Pro uses too). |
| `iPadOS/` | For iPad-only code. Empty for now. iPhone and iPad are one build, so a file here also checks `UIDevice.current.userInterfaceIdiom == .pad` at run time. |
| `visionOS/` | For Vision Pro-only code (`#if os(visionOS)`). Empty for now. |
| `watchOS/` | Watch-only input and speech code. Not in a built target yet. |
| `tvOS/` | Reserved. There is no tvOS target. See [002](decisions/002-per-os-folders.md) and [004](decisions/004-tvos-and-watchos-transport.md). |
| `Tests/GatitaTests/` | The unit tests (XCTest). |
| `Tests/MockServer/` | A local stand-in for the Gatita API, used by the agent-loop tests. |
| `Tests/Fixtures/` | Example plugin folders for the plugin tests. |
| `docs/` | This file and the decision records. |

`Info.plist` and `Gatita.entitlements` are at the top of the repo. The Xcode project uses synchronized folders, so a file added to `App/`, `Shared/`, `macOS/`, `iOS/`, `iPadOS/`, `visionOS/`, `watchOS/`, or `Tests/GatitaTests/` joins its target without a project edit. All of them build for iPhone, iPad, Mac, and Vision Pro, so a file in an OS folder wraps itself in `#if os(...)`: Xcode limits a file to some platforms per file in the project, not per folder. The empty folders hold a `.gitkeep`, which the app target skips (`membershipExceptions`), since Xcode would otherwise copy it into the app.

## Roles and what each host can do

`Shared/Tools/HostPolicy.swift` decides what a host can do, from the platform it runs on.

- **Mac:** project folder, file reads and edits (when turned on), allowed commands in the sandbox, GitHub, calendar, web reads, and pull requests.
- **iPhone, iPad, Vision Pro:** no project folder, so every file tool, command, and PR path is refused. GitHub and calendar are not offered. Web reads, the public connectors, and the ask and report tools remain.

The decision is in [001](decisions/001-question-only-hosts.md).

## Modes and sessions

`GatitaMode` (`Shared/Models/GatitaMode.swift`) has two modes.

- **Chat** is regular chat. No project tools, no commands, no plugin commands, and no GitHub. On the Mac, Chat has no failure-report or question tools (`GatitaMode.usesReportTools`). Connectors you turned on still run, so with Web pages on, a Mac chat can read a public page.
- **Code** works on a project folder: file reads and edits (when turned on), allowed commands, plugin commands, background tasks, subagents, and GitHub.

**PC** (`remote`, on iPhone and iPad only) sends each chat to the paired Mac, which answers with its own key and no project tools. Its chats are kept apart from the Chat tab's.

A saved chat records the mode it was started in (`Conversation.mode`), and the sidebar lists only the chats of the current mode. Switching modes saves the chat on screen and starts a fresh one (`ChatViewModel.switchMode`). Chats saved before modes existed count as Code.

## Background tasks and subagents

`TaskRegistry` (`Shared/Tasks/TaskRegistry.swift`) keeps the background commands and subagents for this run of the app. The model reaches it through five tools, handled in `GatitaClient` before the project tools:

- `run_background`, `task_status`, and `task_stop` start, read, and stop a command that runs past the reply. Background commands use the same sandbox and allow-list as other commands (`macOS/BackgroundProcess.swift`).
- `spawn_agent` and `agent_result` start a subagent and collect its answer. A subagent gets a read-only copy of the project tools (`ProjectTools.readOnlyForSubagents`), with no commands, no edits, and no subagents of its own.

Each tool call records its start and finish time (`ToolActivity.startedAt` and `finishedAt`), so the activity panel can show status and duration.

## Connectors

`Shared/Connectors/Connectors.swift` holds the catalog. A connector's tools are offered only when it is on (in Settings, or with `!name` in the message), and `Connectors.run` sends each tool to its code:

- GitHub (`macOS/GitHubConnector.swift`) reads the project's own repo through `gh`. Calendar (`macOS/CalendarConnector.swift`) reads EventKit. Both are Mac only.
- Web pages (`WebFetch`, `WebCurl`) read public https addresses.
- The public services (`InfoConnectors.swift`: Weather, Wikipedia, DictionaryLookup, CurrencyRates; `CodeConnectors.swift`: PackageInfo, StackOverflow, PublicGitHub) call free APIs that need no key. Each type builds its addresses and turns the JSON into text in pure functions, which the tests check with saved answers. `PublicAPI` does the GET, with a User-Agent that names Gatita, and the shared text helpers. See [007](decisions/007-public-api-connectors.md).

A connector error caused by being offline comes back to the model as "no internet access" (`NoInternet.toolError`), so it tells the user instead of trying again.

## Gatita's look and the newer UI pieces

- `Shared/Views/Theme.swift` holds the colors and `GatitaButtonStyle` (orange primary pill, dark secondary pill, red destructive pill).
- `Shared/Views/GatitaChrome.swift`: `GatitaSheetHeader` (a title and a round close button, used by the Mac Settings and Shop sheets) and `gatitaDialog`, which replaces the system's confirmation dialogs and alerts with a dark card over a dimmed window. Dialogs you type in do not close on an outside tap.
- `Shared/Views/GatitaMenu.swift` replaces the system menus, which draw in the OS's glass style. A screen adds `.gatitaMenuHost()` at its root, and each `GatitaMenuButton` opens a dark card there, under its button or above it when there is no room (`GatitaMenuLayout`). `GatitaTabs` replaces the segmented control. The quick panel lists its skills inside the panel instead, since its window is only as tall as its content.
- `Shared/Views/CodeBlockView.swift` draws code blocks with colors from `Shared/Markdown/SyntaxHighlighter.swift`, a small tokenizer (keywords, types, strings, numbers, comments) with no library.
- `Shared/Models/Speaker.swift` reads replies aloud with `AVSpeechSynthesizer`, from the text `SpeechText` makes. `Shared/Models/VoiceInput.swift` types speech into the prompt box with the Speech framework; its audio and recognizer callbacks are made outside the main actor.
- `MessageActions` handles regenerate and edit: both cut the chat back to before the question and send it again through `ChatViewModel.startReply`, which `send` uses too.
- `Shared/Views/GatitaCommands.swift` is the Chat menu and its shortcuts. `MySkills` keeps your own skills in `my-skills.json`; `ChatExport` and `MarkdownFile` export a chat.
- `macOS/QuickPanel.swift` is the quick panel: a non-activating `NSPanel` that keeps its top edge fixed as it grows, `QuickPanelModel` (one question and answer, in Chat mode, with your connectors), and `QuickPanelView`. `macOS/GlobalHotKey.swift` registers ⌃⌘G with Carbon's `RegisterEventHotKey`, which needs no Accessibility permission. `macOS/CommandDoubleTap.swift` opens it on ⌘ pressed twice, with a listen-only `CGEventTap` (Input Monitoring permission) that feeds `DoubleTapDetector` (`Shared/Models/DoubleTap.swift`), which counts only two quick taps of ⌘ on its own. Screenshots are picked with `macOS/ScreenSelection.swift` (a dimmed, non-activating overlay on every screen: drag an area or click a window, found with `ScreenGeometry` from the window list) and taken by `macOS/ScreenCapture.swift` with ScreenCaptureKit, with all of Gatita's windows (the quick panel and the main window) left out, so only what is behind them is in the picture. They need Screen Recording permission, and `ScreenShot` scales them to at most 1,600 pixels as JPEG before they are attached. See [008](decisions/008-quick-panel.md).

## Saved chats: pins, folders, search, and find

- `Conversation` has optional `pinned` and `folder`, so older `chats.json` files still load. `ChatHistory.updated` saves a chat again with its title, pin, and folder kept.
- `ChatSidebar.sections` groups the sidebar: Pinned, then one section per folder (by name), then the rest, each newest first. A pinned chat shows only under Pinned.
- `ChatSearch` matches a chat by its title or any question or reply (not errors or notices) and makes the snippet shown under it.
- `FindInChat` lists every match in the open chat for the ⌘F bar, steps through them, and marks them in the text. The query reaches every text view through the `findHighlight` environment value.

## Memory

`MemoryStore` (`Shared/Models/Memory.swift`) keeps short facts about the user in `memory.json`: at most 100, of 300 characters each, with no repeats. `SecretCheck` refuses anything that looks like a password, key, token, or card number. `ProjectTools` offers `remember`, `forget`, and `list_memories` when it has a `memoryFile`, on every host and in both modes. Every reply's instructions end with `MemoryStore.instructions`. Settings, Memory lists, adds, and deletes facts, and turns memory off (`AppSettings.memoryEnabled`).

## MCP servers

`Shared/MCP/MCPConfig.swift` covers the pure parts:
- `mcp.json`, in Claude Desktop's `{"mcpServers": {...}}` shape, read into `MCPServerConfig`s;
- tool names (`mcp__<server key>__<tool>`, split back by `MCPConfig.split`);
- the line the model reads for each tool, built from its input schema (`MCPToolParameter`);
- a block's arguments with their JSON types kept.

`MCPHub` (`Shared/MCP/MCPHub.swift`) runs the official swift-sdk's `Client`:
- **Local servers (Mac only).** `MCPProcess` starts the command, found on the login shell's PATH, and hands its stdin and stdout to `StdioTransport`. It refuses in the App Sandbox.
- **Remote servers** use `HTTPClientTransport`.
- **Environment.** A local server gets only a few inherited variables (`MCPProcess.inherited`: HOME, USER, SHELL, TERM, TMPDIR, LANG, …) and its own `env`. The login PATH is worked out once, off the main thread, between markers.
- **Time limits.** A server has 30 seconds (`startTimeout`) to answer when it starts, and a tool call 5 minutes (`callTimeout`). When a limit passes, the hub disconnects the client or cancels the request, which really ends the wait.
- **Stop.** A tool call has a cancellation handler, so Stop ends it at once.
- **Lifecycle.** Each server has a generation number, so a start that finishes after the server was removed or restarted is thrown away. Its tools are listed, and its state (`Status`) shows in Settings, MCP Servers. Local servers are stopped when Gatita quits.

`ProjectTools` takes the tool lines as `extraToolHelp`. `GatitaClient` sends `mcp__` calls to its `mcp` closure, after `approveCommand`, whose rule is the tool name. Trusted servers skip the card. The quick panel and Shortcuts, which can't ask, get only trusted servers' tools (`MCPHub.toolHelp(onlyTrusted:)`), and their runner refuses others. Tests run a real `Client` against `Tests/MockServer/mock_mcp_server.py` over stdio.

## Math and diagrams

`MathDetection` decides which paragraphs and bullets hold math:
- `\(…\)`, `\[…\]`, and `$$…$$` always count;
- a `$…$` span counts only with no space just inside the dollars, and a letter alone or TeX marks;
- code spans never count.

`MathText` draws those with LaTeXSwiftUI. LaTeXSwiftUI would read every pair of dollars as math, so `MathText` first escapes each `$` outside a math span (`MathDetection.escapingStrayDollars`), which keeps "$5 and $10" text even in a paragraph that also holds math. `RichCode` sends `mermaid` blocks to `MermaidBlockView`, which draws them with BeautifulMermaid (`MermaidPicture`, Gatita's colors) after the code stops changing for 350 ms, and falls back to the code block. It sends `math`/`latex` blocks to `MathBlockView`, and `svg` blocks (or `xml` and untagged blocks that start with `<svg`) to `SVGBlockView`. See [009](decisions/009-swift-packages.md).

- **Diagrams are drawn by Gatita, not by the package's image call.** `MermaidPicture` lays the diagram out with the package (`MermaidImageRenderer.prepare`) and draws it on its own canvas whose y axis points down, as the package's drawing expects. The package's own Mac image used a y-up canvas, so every Mac diagram came out upside down. On iPhone and iPad the canvas is pushed as the current UIKit context, since the package draws labels with `NSAttributedString.draw`. One drawing path on every platform means the Mac tests cover the iPad's too.
- **Labels on light boxes.** Gatita's labels are near-white, so `MermaidPicture.readableLabels` adds `color:#1C1C1E` to any `style` or `classDef` line that fills with a light color and names no text color.
- **SVG pictures.** `SVGPicture` (its own file, since SwiftDraw declares a type named `Image`) draws with SwiftDraw on the same kind of canvas, fitted within 2,000 points, on a white card like a browser. iOS can't read SVG itself (`UIImage(data:)` returns nil on iOS 27). Only a self-contained SVG is drawn: after its `xmlns` names are removed, anything with `://`, a `//` link, `url(//…)`, `@import`, or an XML `<!ENTITY` stays a code block, whose Preview blocks the network. SVGs over 500,000 characters stay code too. SwiftDraw itself only decodes inline `data:` images and leaves XML external entities off.
- `ReplyFormat.instructions` tells the model about `mermaid`, `svg`, and math blocks, so it draws with them instead of saying it can't show images.

## Preview, Services, and Shortcuts

- **HTML/SVG preview.** `HTMLPreview` decides which code blocks can be previewed and builds the page: HTML gets a Content-Security-Policy tag allowing only what is inside the page, and SVG is centred in a page. The policy goes first in the page, after any doctype, so nothing runs before it. If the block rules fail to compile, the preview is not shown. `HTMLPreviewSheet` shows it in a `WKWebView` with:
  - a non-persistent data store;
  - a content rule list that blocks every load (`PreviewRules`, compiled once);
  - a navigation delegate that allows only the page itself.
  `HTMLPreviewWebTests` loads a page in a real web view to check that the page shows and a picture from the internet does not.
- **Services menu.** `NSServices` in Info.plist declares "Ask Gatita" (message `askGatita`, port `Gatita`, strings). `GatitaServices` (`macOS/GatitaServices.swift`) is the services provider; `ChatViewModel` registers it at launch and calls `NSUpdateDynamicServices()`. Selected text opens the quick panel with it attached (`QuickPanelModel.selection`, sent through `QuickPanelContext`). The quick panel's shortcuts also start at launch now, so ⌘⌘ and ⌃⌘G work before any window appears.
- **Shortcuts and Siri.** `Shared/Intents/GatitaIntents.swift` has:
  - `AskGatitaIntent`, a question in and the answer out, with a spoken dialog from `IntentAnswer.spoken`;
  - `OpenQuickPanelIntent` (Mac);
  - `GatitaShortcuts`, the App Shortcuts with their Siri phrases.
  An intent reaches the running app through `IntentBridge`, which `ChatViewModel` sets as it starts. `ChatViewModel.answerFromShortcut` answers in Chat mode and saves a new chat without changing the one on screen.

## Scheduled prompts

`Shared/Models/Schedules.swift` holds the model, the math, and the store:
- `ScheduledPrompt` is a name, a prompt, a mode, a `Schedule` (daily, weekdays, weekly, or hourly, at a time), an on/off switch, and the last run.
- `ScheduleMath.nextRun` uses the calendar with `.nextTime` and `.first`, so clock changes give one run a day.
- `ScheduleMath.decision` looks at the latest missed time only. It runs that time if it was due in the last 12 hours, and skips it otherwise.
- The prompts are kept in `schedules.json`.

`ChatViewModel` checks every minute and on `NSWorkspace.didWakeNotification` (Mac only). A run uses its own `GatitaClient`, never the chat on screen. It is saved as a chat in the "Scheduled" folder, titled by `ScheduleMath.chatTitle`, and notifies with `ReplyNotifier.post(…, always: true)`, which shows a banner even while Gatita is in front. `macOS/ScheduledSettingsView.swift` is the Settings page, including "Open Gatita at login" (`SMAppService.mainApp`).

## Checkpoints

`CheckpointRecorder` (`Shared/Tools/Checkpoints.swift`) is made for each Code reply that may write. `GatitaClient` calls `before` ahead of each `write_file` or `edit_file`, which keeps the file as it was before the reply's first change to it (or none, for a file the reply makes). It calls `after` once the change worked, which keeps the latest text and saves `checkpoints/<reply id>.json`.

`CheckpointStore.undo` puts each file back and removes files the reply made. Paths must stay inside the project (links are resolved), and links and `.git` are never written. When regenerate or edit drops replies, the new reply's recorder takes over their checkpoints (`inheriting:`), so its undo goes back to before them. Without `force`, a file changed since the reply stops the undo and is reported, and the chat asks "Undo anyway?". Changes made by commands are not recorded, and checkpoints older than 30 days are deleted at launch.

## Asking before commands

Before `run_command` or `run_background`, `GatitaClient` awaits `approveCommand` with the command and its rule. The rule is the allowed command it matched (`CommandApproval.rule`, such as `swift test`), which covers that command with any arguments. `ChatViewModel.approveCommand`:
- allows it at once when asking is off or a saved rule for this project covers it;
- otherwise shows `CommandApprovalCard` and waits on a continuation;
- posts a notification while Gatita is in the background.

Your answer is Allow once, Always allow (saved in `AppSettings.commandRules` by project folder), or Deny. A denial is sent back to the model as an error, and Stop denies a waiting command.

`CommandApproval.decision` holds the rule, and its tests cover it:
- a trusted MCP server's tools, or anything always allowed, run without asking;
- commands also run without asking when "Ask before each command" is off;
- an untrusted MCP tool is always asked about.

A scheduled run is unattended, so anything it would ask about is denied instead, and it never takes the chat's one approval card. Clicking the notification for the chat already on screen only brings Gatita forward, so it does not stop the reply. Commands that are not allowed at all, or with commands off, are left for the tool to refuse.

## Notifications and the menu bar

`ReplyNotifier` (`Shared/Models/Notifier.swift`) sends a system notification when a reply finishes, asks a question, or fails, and when a background command ends on its own (`TaskRegistry.onTaskFinished`), but only while Gatita is not the app in front. `Notifier` makes the text, and clicking a notification opens its chat. There is no finished-reply badge. The menu bar item (`macOS/MenuBarStatus.swift`) is inserted only while `ChatViewModel.showsMenuBarItem` is true: a background command or subagent is running, or the Mac is kept awake.

## Changes and the activity panel

Before a write or edit runs, `ProjectTools.changePreview` works out the change as a diff (`LineDiff`). The change is attached to the tool call only when the edit succeeds. In Code mode, the activity panel (`macOS/ActivityPanel.swift`) lists tool calls, background tasks, subagents, and changed files.

## Replies on screen

`MarkdownBlocks` splits a reply into headings, bullets and numbered items (with their depth), checklists (`ChecklistItem`), callouts and quotes (`CalloutKind`), rules, code, tables (with `TableAlignment`), and charts. A `chart` code block holding valid JSON (`ChartSpec`: a `type` of bar, line, or pie, an optional `title`, and up to 50 `points` of a label and a number) is drawn with Swift Charts in `ChartBlockView`; anything else stays a code block. `Shared/Views/RichBlocks.swift` draws checklists, callouts, numbered steps, and tables; a table whose column is all numbers can switch to a chart (`TableChart`). Every reply's system text starts with `ReplyFormat.instructions`, which tells the model what the chat can draw.

Under a finished reply:
- its tokens (`TokenUsage`): read from the stream when the server sends them, otherwise estimated by `TokenEstimate` and marked as an estimate;
- the buttons (`MessageActions`): copy, fork, pin, and reply;
- the time (`ReplyTime`).

`/usage` is answered in the chat from the saved counts (`UsageReport`), and is never sent to Gatita. `TranscriptView` decides how much besides the text shows. Your own instructions (`CustomInstructions`) are added before the skill's instructions on every reply. A reply that leaks a control token is stopped as soon as the token arrives (`ReplyCheck.stopsStream`).

In Code mode on the Mac, `macOS/ProjectBar.swift` shows the folder and the git worktree and branch, read by `RepoStateLoader` and parsed by `GitWorktrees`.

## How a request flows

1. `ChatViewModel.send` adds the message and starts a `GatitaClient` with the tools for this host.
2. `GatitaClient.stream` sends the chat to `POST /v1/chat/completions` with `stream: true`, and reads the reply as it arrives.
3. The model writes tool calls as `<gatita-tool>` blocks in its text. The client stops at the first complete block, runs it through `ProjectTools.execute`, and sends the result back as `<gatita-tool-result>`. `ask_user` ends the turn and shows the question.
4. Text, reasoning, and tool events come back as `StreamEvent`s and update the reply on screen. Tools run off the main actor (`ProjectTools.execute` is `@concurrent`), so a long command does not block the window. An HTTP 429 is waited out (`RateLimit`: the Retry-After header or the body's `retryAfter`, at most 75 seconds, twice per turn) and the turn sent again; the wait reaches the chat as a `.waiting` event and a countdown. A turn with no tool call is judged by `TurnEnding`: if it wrote nothing, hit the length limit, was cut off inside a tool block, or ended in a colon with no tool call, the client asks the model to go on (at most `GatitaClient.maxNudges` times), and an ending that stays bad becomes a `GatitaError.endedEarly` with the reason. A tool block whose closing tag is missing still runs when its JSON is whole. The `batch` tool (`ToolBatch`) runs up to 10 calls in one step: the client runs each in order as its own tool call in the chat, and sends back one result with each answer between start and end lines. `read_files` expands folders and glob patterns (`ReadFiles.matches`) and marks where each file starts and ends; `web_fetch` reads up to 5 pages at once (`WebFetch.fetchMany`). Every tool reads its arguments with `ToolArguments`, which accepts text, numbers, and lists, and repairs raw line breaks in strings, a code fence or words around the object, trailing commas, and the OpenAI `{"name", "arguments"}` shape. A failed call's error says what would work: the tool names (`ProjectTools.toolNames`, read from the instructions), the allowed commands, or files with the same name. `ToolRepeat` adds a note to the result of a call that repeats the one before it; the note goes to the model only.
5. A host that is serving a client does the same, and sends each piece to the client as a `RemoteMessage.chunk` over MultipeerConnectivity, then the whole reply as a `response`. `ReplyAssembler` builds the reply on the client side.

Replies with leaked control tokens (such as `<|close|>`) are dropped and a failure report is written.

`Connectivity` (`Shared/Networking/Connectivity.swift`) watches the network path with `NWPathMonitor`. While there is none, the chat shows a "No internet access" banner, and `ChatViewModel.send` answers a new message with "Error: No internet access." without contacting the server (except in the PC tab, which talks to the Mac over the local network). A request that fails with an offline error gets the same message. Offline errors and rate limits write no failure report, since neither is a bug.

## Storage

Everything stays on the device. Nothing is sent to a service other than the Gatita API and the connectors the user turns on.

| What | Where |
|---|---|
| API key | Keychain (service `Gatita`, account `gatita-api-key`) |
| Settings | `~/Library/Application Support/Gatita/settings.json` (no key), including always-allowed commands per project |
| Memory | `…/Gatita/memory.json` |
| Scheduled prompts | `…/Gatita/schedules.json` |
| MCP servers | `…/Gatita/mcp.json` (Claude Desktop's shape; may hold tokens you typed in a server's environment) |
| Checkpoints | `…/Gatita/checkpoints/<reply id>.json` (30 days) |
| Chats | `…/Gatita/chats.json` |
| Log and failure reports | `…/Gatita/logs/gatita.log` and `…/logs/failures/` |
| Analytics | `…/Gatita/logs/analytics.json` (counts only) |
| Plugins | `…/Gatita/plugins/<folder>/plugin.json` |

## Safety

- File tools stay inside the project folder, refuse `..` and absolute paths, and never touch `.git`. Writes need the user's switch.
- Commands come from a fixed allow list, never run through a shell, and run in a sandbox profile that denies network and writes outside the project.
- Web reads are https only, and refuse localhost and private addresses.
- GitHub reads use fixed `gh` commands with the repository taken from the git remote.
- Calendar reads need the user's permission. The Release build's sandbox has the calendar entitlement, and the Info.plist has the usage text.

## Recent decisions

- [001](decisions/001-question-only-hosts.md): question-only hosts on iPhone, iPad, and Vision Pro.
- [002](decisions/002-per-os-folders.md): one folder per operating system for OS-only code.
- [003](decisions/003-hosted-shop-deferred.md): the hosted shop waits for a reviewed, signed catalog.
- [004](decisions/004-tvos-and-watchos-transport.md): how tvOS and watchOS clients reach a host (open).
- [007](decisions/007-public-api-connectors.md): connectors for free public services, with no keys.
- [008](decisions/008-quick-panel.md): the quick panel and its global shortcut.
- [009](decisions/009-swift-packages.md): the first Swift packages, for math, diagrams, and MCP.

## Tests

The unit tests run on the Mac:

```bash
xcodebuild -project Gatita.xcodeproj -scheme Gatita -destination 'platform=macOS' test
```

They cover the tools and their sandbox, the agent loop against the mock server, commands and plugins, pull-request planning, the composer and connectors, persistence, chat history, host rules, streamed replies, and the calendar window and listing.
