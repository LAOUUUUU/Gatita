# Gatita

[![Tests](https://github.com/LAOUUUUU/Gatita/actions/workflows/tests.yml/badge.svg?branch=dev)](https://github.com/LAOUUUUU/Gatita/actions/workflows/tests.yml)

A SwiftUI chat app for Gatita's API, for Mac, iPhone, iPad, and Apple Vision Pro. The Mac is the full host, with project tools. iPhone, iPad, and Vision Pro are hosts that answer questions. Other platforms will be clients. See [ROADMAP.md](ROADMAP.md) and [docs/architecture.md](docs/architecture.md).

## What it does

- Chat with Gatita, with streamed replies and visible thinking.
- **Quick panel (Mac):** press ⌘ twice quickly (⌘⌘), or ⌃⌘G, in any app for a floating Gatita box, like Spotlight. Ask, read the answer, and press Escape. Like Claude's quick entry, ⌘⌘ opens the panel and the screenshot picker together: the screens dim, and you drag over an area or click a window (it is outlined as you point at it). The screenshot is attached to the panel, and the panel itself is never in the picture. Escape, or a click on the panel, skips it. The camera button takes one any time, and each screenshot shows as a thumbnail you can take out before sending. The clipboard button sends your clipboard's text along with the next question only (it turns off after each one), the chip picks a skill, and "Open in Gatita" keeps the question and answer as a saved chat. It is also in the Chat menu.
- **Edit and regenerate:** the pencil under your message edits it and sends it again; the arrow under a reply answers again, with the chosen model or the other one. What came after is replaced.
- **Code blocks** have colors for Swift, Python, JavaScript and TypeScript, JSON, shell, SQL, and other common languages, plus the language name and a Copy button.
- **Read aloud:** the speaker under a reply reads it out with the system voice, skipping code and Markdown marks.
- **Voice input:** the mic in the prompt box types what you say. Press it again to stop. The first time, the system asks for microphone and speech recognition permission.
- **Keyboard:** ⌘N new chat (it also brings the window back after you closed it), ⌘. or Escape stops a reply (Escape closes an open menu or dialog first), ⌘R regenerates the last reply, ⌘⇧C copies it, ⌘⇧L reads it aloud, ⌘K opens the skill menu, and ⌃⌘G opens the quick panel. A round arrow button jumps to the newest message when you scroll up.
- **Saved chats:** right-click (or long-press) a chat to pin it to the top, move it into a folder (or make a new one), rename it, export it as a Markdown file, or delete it. The sidebar shows Pinned first, then each folder (click its name to fold it), then the rest. The `…` next to "Chats" deletes all chats in the current mode, after you confirm.
- **Search and find:** the sidebar search looks inside every question and reply, not just titles, and shows the words around the match. ⌘F opens a find bar over the open chat: matches are marked in orange, Return or ⌘G goes to the next, ⇧⌘G to the one before, and Escape closes it.
- **PDFs:** drop a PDF on the prompt box (or attach it) and Gatita reads its text; the card shows its page count. A scanned PDF with no text says so.
- **Memory:** Gatita remembers short facts you tell it (your name, preferences, projects) across chats, with the `remember` and `forget` tools, and reads them before every reply. Settings, then Memory, lists them: delete any, add your own, forget everything, or turn memory off. They stay on this device, at most 100 facts, and anything that looks like a password, key, or card number is never saved. When a reply saves or removes a fact, the chat says so, and facts reach the model as information, never as instructions to follow.
- **MCP servers:** Settings, then MCP Servers, connects Gatita to MCP servers (thousands exist, such as Notion, Linear, GitHub, databases, or your files): a local one Gatita starts on the Mac (a command such as `npx -y @modelcontextprotocol/server-github`, its arguments, and environment) or a remote one at an https address (any device). Their tools join the chat in both modes, named `mcp__<server>__<tool>`. Each call asks first (Allow once, Always allow that tool, or Deny) unless you mark the server Trusted, even with "Ask before each command" off; only trusted servers' tools work in the quick panel and Shortcuts. The list is kept in `mcp.json` in the shape Claude Desktop uses, and "Import from Claude Desktop" copies its servers. Local servers run outside Gatita's command sandbox, so add only ones you trust; they need the Debug build (App Sandbox off). A server gets only a few basic variables from Gatita's environment (HOME, USER, PATH, and the like) plus its own, never Gatita's API key. A server has 30 seconds to start and a tool call 5 minutes; Stop ends a waiting call at once.
- **Math and diagrams:** math in a reply (`$x^2$`, `\(…\)`, `$$…$$`, `\[…\]`, or a `math` block) is drawn as typeset math, a `mermaid` block (flowchart, sequence, state, class, ER, or XY chart) as a diagram in Gatita's colors, and an `svg` block as a picture on white, with a Code button to see its source. Prices such as "$5 and $10" stay text. A diagram type that can't be drawn stays a code block, and so does an SVG that links to anything outside itself (a web address, a file, or a style sheet), which keeps its sandboxed Preview. The model is told it can draw this way, so it doesn't say it can't show pictures.
- **HTML and SVG preview:** an `html` or `svg` code block has a Preview button that shows the page live in a sheet. Scripts run, but nothing in the preview can reach the network or leave the page.
- **Ask Gatita from any app (Mac):** select text anywhere, right-click, and choose Services, then Ask Gatita. The quick panel opens with that text attached; type a question or press Return to have it explained. (macOS lists the service for Gatita in /Applications.)
- **Shortcuts and Siri:** "Ask Gatita" is an action in the Shortcuts app and works by voice ("Ask Gatita"). It answers in Chat mode with your connectors and memory, returns the answer to the shortcut, has Siri say a short version, and saves the question and answer as a chat. On the Mac, "Open the Gatita quick panel" is one too.
- **Scheduled prompts (Mac):** Settings, then Scheduled, runs prompts on their own every day, on weekdays, once a week, or every hour, at a time you pick, in Chat or Code mode. Each run is saved as a chat in the Scheduled folder and sends a notification. They run while Gatita is open (the menu bar cat shows during a run). A run missed while the Mac slept runs when it wakes, if it was due in the last 12 hours. "Open Gatita at login" keeps them going after a restart. A scheduled run never waits for an answer: a command or MCP tool it would have to ask about is denied, unless you always allowed it (or trusted its server).
- **Undo a reply's changes (Mac, Code mode):** a reply that wrote or edited files gets a ↩︎ button that puts every file back as it was before the reply and removes files it made. If you changed one of them since, Gatita asks first. As in Claude Code, changes made by commands are not undone. Checkpoints are kept for 30 days. Regenerating or editing a question keeps them: the new reply's ↩︎ undoes the replaced replies' changes too.
- **Ask before commands (Mac):** each command Gatita wants to run waits for your answer: Allow once (Return), Always allow (that command with any arguments, saved for this project), or Deny (Escape). A notification says when one is waiting while Gatita is in the background. Settings, then Project, turns asking off and lists the always-allowed commands.
- **My skills:** in Settings, then Skills, write your own skills (a name and instructions). They show with `/` like the built-in ones.
- Menus, dialogs, tabs, and sheets use Gatita's look instead of the system's glass: dark cards with an orange check on the current choice, orange and dark pill buttons, and a round close button. This covers the transcript view, regenerate, worktree, and chat menus, and the Shop's tabs.
- Saved chats in the sidebar, titled by Gatita. A chat stays in the mode it was started in: Code chats appear only in Code, and Chat chats only in Chat. Each prompt has a line on the right edge of the chat; click one to jump to that prompt.
- When a reply finishes, Gatita asks you something, or a reply fails while Gatita is not the app in front, you get a system notification with the chat's title and the start of the reply; clicking it opens that chat. Nothing badges the app or the menu bar for that. The menu bar cat shows only while a background command or subagent runs (with how many, and a way to stop each) or while the Mac is kept awake, and a background command that ends on its own sends a notification too. Quitting Gatita stops every background command it started. The first message you send asks for notification permission.
- On a Mac, Gatita can read and search a project folder, run allowed commands in a macOS sandbox, read GitHub pull requests and issues through `gh`, read your calendar events (read-only), and read public web pages.
- On iPhone, iPad, and Vision Pro, Gatita answers questions, reads public web pages, and uses the public connectors below. Project files, commands, GitHub, and pull requests are only on the Mac.
- Connectors that read free public services, with no key or sign-in, on every device. Each stays off until you turn it on in Settings, then Connectors, or type its `!name` in a message, and each sends only what you ask about to that one service:
  - `!weather`: weather now and a forecast of up to 7 days for any place (Open-Meteo).
  - `!wikipedia`: search Wikipedia and read a page's summary, in any language.
  - `!dictionary`: English definitions, examples, and synonyms (dictionaryapi.dev).
  - `!currency`: daily exchange rates from the European Central Bank (frankfurter.dev).
  - `!packages`: the latest version, license, and links of a package on npm, PyPI, crates.io, or the Go module proxy, so Gatita checks versions instead of guessing them.
  - `!stackoverflow`: search Stack Overflow and read the top answers, code included, with a link back (about 300 reads a day).
  - `!repos`: any public GitHub repository without a login: its facts, newest release, and README (60 reads an hour).
- With no internet, a red "No internet access" banner sits at the top of the chat, and a message sent then gets "Error: No internet access." instead of a failed request. What you typed stays in the prompt box. The PC tab still works, since it talks to your Mac over the local network.
- When Gatita's API rate limit is reached (HTTP 429), the reply waits as long as the server asks, up to 75 seconds, with a countdown above the prompt box, and then goes on, up to twice per step.
- In Code mode, Gatita can run an allowed command in the background and check or stop it later, and start subagents that read the project and answer in parallel. The Activity panel on the right lists tool calls, background tasks, subagents, and changed files.
- In Code mode, each file change shows as a diff in the chat, with the path, the added and removed line counts, and the changed lines in red and green.
- Skills, picked with `/`: Code review, Write tests, Web design review, Explain code, Charts, Debug, Refactor, Commit message, Write docs, Security check, Check dependencies, Research, Summarize, Study helper, and Writing help.
- Pick skills with `/`, project files with `@` (or the `@` button), and plugins or connectors with `!`. The paperclip opens a file picker, and the chosen files show as cards in the prompt box.
- Attach a text file or a picture (PNG, JPEG, GIF, or WebP up to 4 MB) by dropping it on the prompt box or with the paperclip. Each shows as a card inside the box until you send. Pictures are sent to Gatita as images, which the API docs do not describe yet. On a Mac, a paste of 2,000 characters or more becomes a `Pasted text.md` attachment. Files over 2 MB, folders, and files that are not UTF-8 text are refused.
- A Shop with free plugins, skills, and connectors bundled with the app.
- On a Mac, turn on "Keep the Mac awake" in Settings (or the menu bar, while the cat shows) to stop it sleeping on its own while Gatita is open. Closing the lid can still sleep it, and a sleeping Mac cannot run Gatita.
- Pairing: on a Mac, open Settings, then Pairing, and press "Allow devices for 5 minutes". The Mac shows a new code. On the phone or iPad, type that code, pick the Mac under Nearby, and connect. The PC tab on the phone or iPad sends its chats to the paired Mac, which answers with its own key and no project tools. The chat says whether it is connected. The code stops working when the time is up. Pairing works only on the same local network, and only while the Mac allows it.
- Replies draw Markdown richly, and every reply tells Gatita what the chat can draw, so it uses these when they help: numbered steps with orange badges; checklists (`- [ ]`, `- [x]`) with a progress bar ("2 of 5 done"); callouts (`> [!TIP]`, `> [!NOTE]`, `> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]`) and quotes; nested lists; rules; and tables with column alignment, striped rows, Copy, and a Table/Chart switch when a column holds numbers. Charts (bar, line, pie) come from a `chart` block of JSON with a `type`, a `title`, and up to 50 `points`; a block that is not valid chart data stays as code.
- Transcript view: Normal shows only the text Gatita writes, Thinking adds its thinking and tool calls folded, and Verbose shows everything open. Choose it from the menu in the Mac chat header, or in Settings.
- Under each reply: its token count (estimated at about four characters a token, and marked as an estimate, when the server reports none), buttons to copy, fork the chat from there, pin, or reply with a quote, and the time. Type `/usage` for the totals.
- Settings, then Instructions, holds your own instructions, which Gatita reads before every reply.
- In Code mode on a Mac, a bar above the prompt shows the project folder, whether it runs locally, and the git worktree and branch (switch worktrees from its menu). A running background task gets a stop button there.
- Gatita stops a reply the moment a control token such as `<|close|>` shows up in it.
- A reply that ends for no good reason is not left hanging. If nothing was written, the length limit cut it off, a tool call was cut off or its closing tag was missing, or it ended in a colon with no tool call, Gatita asks the model to go on, up to twice, and then says why the reply ended.
- Fewer requests for the same work: `batch` runs up to 10 tool calls in one step and sends all the results back at once. `read_files` reads up to 20 project files in one call, takes folders and patterns such as `Shared/**/*.swift`, and puts each file between a "===== start of <path> =====" line and an "===== end of <path> =====" line. A pattern that can't be read, such as one with an unclosed `[`, says so instead of matching nothing. A path that exists is read as written even with `[` in its name (`app/[id]/page.tsx`), and, as in a shell, folders and patterns leave out hidden files such as `.env` unless the pattern names one (`**/.env`). `web_fetch` reads up to 5 pages in one call. `find_files` finds files by part of their name, and `search_text` can ignore case and stay in one folder.
- Tool calls forgive the model's usual slips: raw line breaks inside a text, a code fence around the JSON, trailing commas, and the OpenAI shape `{"name": ..., "arguments": {...}}`. Arguments can be text, numbers, or lists. When a call still goes wrong, the error says how to fix it: the tools that exist, the commands that are allowed, or the files with that name. The same call twice in a row is pointed out to the model. Tools run off the main thread, so a long command never freezes the window. One reply can make up to 40 rounds of tool calls.
- Logs, analytics, and failure reports stay on your device.

## Build

1. Open `Gatita.xcodeproj` in Xcode. It fetches the Swift packages below the first time (pinned in `Package.resolved`).
2. Choose the Gatita scheme and a Mac, iPhone, iPad, or Vision Pro destination.
3. Run.

Swift packages (see [decision 009](docs/decisions/009-swift-packages.md)):

| Package | For | License |
|---|---|---|
| [LaTeXSwiftUI](https://github.com/colinc86/LaTeXSwiftUI) 2.x, with MathJaxSwift, SwiftDraw, and swift-html-entities | Math in replies | MIT |
| [BeautifulMermaid](https://github.com/lukilabs/beautiful-mermaid-swift) 1.x, with elk-swift | Mermaid diagrams, drawn natively | MIT |
| [MCP swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) 0.12.x, with swift-log, swift-system, and EventSource | MCP servers | Apache 2.0 / MIT |

The Debug build turns off App Sandbox, so the Mac can read your project folder and reach the network. The Release build keeps the sandbox on. It allows outgoing connections (for the API), incoming connections (for talking to your other devices), calendar access, the microphone (for voice input), and reading and writing files you choose (for exporting a chat). The Apple Watch source is in the repo but is not built yet.

## Setup

- In Settings, paste your Gatita API key. It is saved in the Keychain, never in a file.
- On a Mac, set the project folder in Settings, for example `~/Documents/Gatita`. Other devices do not have one.
- Other settings are saved in `~/Library/Application Support/Gatita/settings.json`.
- Hosts talk to other devices on your local network. The first time, the system asks for local network access. Allow it, or those devices cannot reach the host.
- Calendar: the first time you ask about your schedule, macOS asks for calendar access. Allow it under Privacy & Security, Calendars.
- Voice input: the first time you press the mic, the system asks for microphone and speech recognition access.
- The quick panel opens with ⌘⌘ or ⌃⌘G. ⌘⌘ needs Input Monitoring permission (System Settings, Privacy & Security, Input Monitoring); Gatita asks once, and Settings, then Quick panel, shows whether it works and opens that page. Gatita only notices whether ⌘ was pressed on its own; it never records what you type. A Debug build loses the permission each time it is rebuilt, so turn it on again after an update. ⌃⌘G and the Chat menu need no permission. Screenshots need Screen Recording permission (Privacy & Security, Screen Recording); Gatita asks once, and the panel and Settings, then Quick panel, say when it is missing. "⌘⌘ starts with a screenshot" can be turned off there.
- Your own skills are saved in `~/Library/Application Support/Gatita/my-skills.json`.

## Plugins

A plugin is a folder with a `plugin.json` in `~/Library/Application Support/Gatita/plugins/`. It can add skills and commands. Commands run in a macOS sandbox with no network. The Shop installs plugins this way.

## Safety

- The API key is never written to the repo or to `settings.json`.
- Edits and commands stay off until you turn them on in Settings, and they only exist on the Mac.
- A message that matches a local safety rule (`Shared/Safety/SafetyFlags.swift`) is refused on the device, and Gatita is never asked. The starting rules cover explosives and malware.
- Connectors only read. Calendar reads events and never changes them. The public connectors send only the words of the request (a place, a search, a package name) to the one service named, with a User-Agent that names Gatita.
- Creating a pull request runs git and gh only after you confirm.

## Versions

Gatita is an alpha, version 0.0.7. The version has three numbers, MAJOR.MINOR.PATCH:

- **MAJOR** (first number): a big refactor or a huge update.
- **MINOR** (second number): new models.
- **PATCH** (third number): updates, bug fixes, and small changes.

No number resets. Each one keeps counting up, so after 0.0.2, a release with new models is 0.1.3, and a big refactor after that is 1.2.4.

The version shows in Settings, under About. Each release is listed in [CHANGELOG.md](CHANGELOG.md). When the version changes, set the version in Xcode (MARKETING_VERSION) and add the changelog entry in the same commit. A test fails if the newest changelog entry does not match the app version.

## Releases

`scripts/release.py` bumps the version and builds the release files: the macOS zip, the iPhone and iPad `.ipa`, checksums, and a Sideloadly guide, in `~/Documents/Gatita-releases/<version>-alpha/`.

```bash
python3 scripts/release.py release 0.0.5
```

Use `bump` to change only the version, and `build` to rebuild the current version after a fix. Run `python3 scripts/release.py --help` for the options. The script does not commit, tag, or publish. Add the changelog entry before you build.

A build takes about 10 minutes: the tests, the Mac app, the iPhone and iPad app, then packaging. While it runs, one line shows the step, a bar, how far along the whole build is, and the time so far, and each finished step leaves a ✓ line with its time:

```text
✓ Tests  2:08
Step 2 of 4  Mac app  ██████████░░░░░░░░░░░░░░░░░░░░  35%  3:31
```

The percentage is an estimate from the last build's step times and log lengths (kept in `~/Documents/Gatita-releases/release-steps.json`), so it gets better after each build. The xcodebuild logs go to a temporary folder printed at the start; when a step fails, its last 25 lines are shown.

## Tests

Run the unit tests on the Mac:

```bash
xcodebuild -project Gatita.xcodeproj -scheme Gatita -destination 'platform=macOS' test
```

The agent-loop tests start a local mock of the Gatita API from `Tests/MockServer` with `/usr/bin/python3`, on port 8765. Set `MOCK_PORT` to use another port.

The public connectors are tested with saved answers, so the normal run needs no internet. To check them against the real services as well:

```bash
TEST_RUNNER_GATITA_LIVE_TESTS=1 xcodebuild -project Gatita.xcodeproj -scheme Gatita -destination 'platform=macOS' test -only-testing:GatitaTests/LiveConnectorTests
```

To see the offline screen without unplugging anything, launch the app with `GATITA_FORCE_OFFLINE=1`.

The release script has its own tests: `python3 -m unittest discover -s scripts`.

GitHub Actions runs all of this on a clean Mac for every push to `dev` and `main` that changes more than docs (`.github/workflows/tests.yml`): the release-script tests, the macOS tests, and the iOS simulator build, with Xcode 27.0 on GitHub's `xcode-27` runner. A failed run keeps its logs and test results for 7 days. Work happens on `dev`, which goes to `main` only once this passes.

## License

MIT. See [LICENSE](LICENSE).
