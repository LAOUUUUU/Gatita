# Architecture

Gatita is one SwiftUI app with several targets. The Mac is the full host. iPhone, iPad, and Vision Pro are hosts that answer questions. See [ROADMAP.md](../ROADMAP.md) for the platform roles and the plan.

## Folders

| Folder | What is in it |
|---|---|
| `App/` | The app entry point (`GatitaApp.swift`) and the asset catalog (icons, logo, menu bar icon). |
| `Shared/` | Code for every platform that builds it: networking, tools, connectors, models, view model, views, shop, settings, chat history, logging, safety rules, and the task registry (`Shared/Tasks`). |
| `macOS/` | Code that only makes sense on the Mac: the sandboxed command runner and background process, the web check, the GitHub and Calendar connectors, the git process runner, the menu bar, the file tree, the pull-request sheet, the mode switch, the activity panel, and the sleep guard. |
| `watchOS/` | Watch-only input and speech code. Not in a built target yet. |
| `iOS/`, `visionOS/`, `tvOS/` | Reserved for code that only that OS needs. Empty for now. See [002](decisions/002-per-os-folders.md). |
| `Tests/GatitaTests/` | The unit tests (XCTest). |
| `Tests/MockServer/` | A local stand-in for the Gatita API, used by the agent-loop tests. |
| `Tests/Fixtures/` | Example plugin folders for the plugin tests. |
| `docs/` | This file and the decision records. |

`Info.plist` and `Gatita.entitlements` are at the top of the repo. The Xcode project uses synchronized folders, so a file added to `App/`, `Shared/`, `macOS/`, `watchOS/`, or `Tests/GatitaTests/` joins its target without a project edit.

## Roles and what each host can do

`Shared/Tools/HostPolicy.swift` decides what a host can do, from the platform it runs on.

- **Mac:** project folder, file reads and edits (when turned on), allowed commands in the sandbox, GitHub, calendar, web reads, and pull requests.
- **iPhone, iPad, Vision Pro:** no project folder, so every file tool, command, and PR path is refused. GitHub and calendar are not offered. Web reads and the ask and report tools remain.

The decision is in [001](decisions/001-question-only-hosts.md).

## Modes and sessions

`GatitaMode` (`Shared/Models/GatitaMode.swift`) has two modes.

- **Chat** is regular chat. No project tools, no commands, no plugin commands, and no GitHub. Web reads and calendar stay available.
- **Code** works on a project folder: file reads and edits (when turned on), allowed commands, plugin commands, background tasks, subagents, and GitHub.

A saved chat records the mode it was started in (`Conversation.mode`), and the sidebar lists only the chats of the current mode. Switching modes saves the chat on screen and starts a fresh one (`ChatViewModel.switchMode`). Chats saved before modes existed count as Code.

## Background tasks and subagents

`TaskRegistry` (`Shared/Tasks/TaskRegistry.swift`) keeps the background commands and subagents for this run of the app. The model reaches it through five tools, handled in `GatitaClient` before the project tools:

- `run_background`, `task_status`, and `task_stop` start, read, and stop a command that runs past the reply. Background commands use the same sandbox and allow-list as other commands (`macOS/BackgroundProcess.swift`).
- `spawn_agent` and `agent_result` start a subagent and collect its answer. A subagent gets a read-only copy of the project tools (`ProjectTools.readOnlyForSubagents`), with no commands, no edits, and no subagents of its own.

Each tool call records its start and finish time (`ToolActivity.startedAt` and `finishedAt`), so the activity panel can show status and duration.

## Changes and the activity panel

Before a write or edit runs, `ProjectTools.changePreview` works out the change as a diff (`LineDiff`). The change is attached to the tool call only when the edit succeeds. In Code mode, the activity panel (`macOS/ActivityPanel.swift`) lists tool calls, background tasks, subagents, and changed files.

## How a request flows

1. `ChatViewModel.send` adds the message and starts a `GatitaClient` with the tools for this host.
2. `GatitaClient.stream` sends the chat to `POST /v1/chat/completions` with `stream: true`, and reads the reply as it arrives.
3. The model writes tool calls as `<gatita-tool>` blocks in its text. The client stops at the first complete block, runs it through `ProjectTools.execute`, and sends the result back as `<gatita-tool-result>`. `ask_user` ends the turn and shows the question.
4. Text, reasoning, and tool events come back as `StreamEvent`s and update the reply on screen.
5. A host that is serving a client does the same, and sends each piece to the client as a `RemoteMessage.chunk` over MultipeerConnectivity, then the whole reply as a `response`. `ReplyAssembler` builds the reply on the client side.

Replies with leaked control tokens (such as `<|close|>`) are dropped and a failure report is written.

## Storage

Everything stays on the device. Nothing is sent to a service other than the Gatita API and the connectors the user turns on.

| What | Where |
|---|---|
| API key | Keychain (service `Gatita`, account `gatita-api-key`) |
| Settings | `~/Library/Application Support/Gatita/settings.json` (no key) |
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

## Tests

The unit tests run on the Mac:

```bash
xcodebuild -project Gatita.xcodeproj -scheme Gatita -destination 'platform=macOS' test
```

They cover the tools and their sandbox, the agent loop against the mock server, commands and plugins, pull-request planning, the composer and connectors, persistence, chat history, host rules, streamed replies, and the calendar window and listing.
