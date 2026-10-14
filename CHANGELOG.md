# Changelog

Gatita uses three numbers, MAJOR.MINOR.PATCH, plus a channel while it is not final:

- **MAJOR** (first number): a big refactor or a huge update.
- **MINOR** (second number): new models.
- **PATCH** (third number): updates, bug fixes, and small changes.

No number resets. Each one keeps counting up, so after 0.0.2, a release with new models is 0.1.3, and a big refactor after that is 1.2.4.

## 0.0.8 alpha

Roblox help, formulas and diagrams that draw right, and a start-up fix for long device names.

- **Roblox.** A Roblox skill (type `/roblox`). In Code mode, a Roblox chip shows in the bar above the prompt when the project folder is a Roblox project: a Rojo project, or script files named like `Main.server.luau`. Point at the chip to see how edits reach Roblox Studio.
- **Code colors.** Lua and Luau blocks have colors of their own: `--` comments, `--[[ ]]` comments and `[[ ]]` strings, backtick strings, and the language's keywords. Before, `//` (Luau's floor division) was drawn as a comment.
- **Math.** Formulas that failed right after a number, such as `x_{n=1}` and `-2\pi`, now draw, and formulas on the Mac are no longer half size. Gatita builds a patched copy of its math package until the fixes that are waiting upstream are released.
- **Diagrams.** Mermaid diagrams are the right way up on the Mac, and their labels show on iPhone and iPad. An `svg` block draws as a picture with a Code button, and Gatita now tells the model it can draw with mermaid, svg, and math.
- **Fixes.** A Mac or iPhone whose name is longer than 63 bytes (or empty) no longer causes errors when Gatita starts. The project bar no longer shows an old folder's git branch or Roblox chip if you pick another folder quickly.
- **Under the hood.** Code that belongs to one system now lives in a folder for it (macOS, iOS, iPadOS, visionOS). The tests and the iOS build run on GitHub Actions for every push to `dev` and `main`. The release script shows a progress bar.

## 0.0.7 alpha

A quick panel, richer replies, memory, math and diagrams, MCP servers, and more ways to reach Gatita.

- **Quick panel (Mac).** Press ⌃⌘G, or ⌘ twice, to ask from any app. Pressing ⌘ twice also lets you drag over an area or click a window to attach a screenshot; Gatita's own windows are left out.
- **Find.** The sidebar search looks through every message, and ⌘F finds words in the open chat and highlights them.
- **Pinned chats and folders.** Pin a chat or move it to a folder from its menu in the sidebar.
- **Memory.** Gatita can remember facts across chats. See, add, and delete them in Settings, Memory. It refuses anything that looks like a password or key, and a chat says when something was remembered.
- **Replies.** Math is drawn as typeset math, and `mermaid` blocks as diagrams. Checklists, callouts, quotes, nested lists, and numbered steps; tables can be copied or shown as a chart. Code blocks have colors, and HTML and SVG blocks have a preview that can't reach the internet. Edit a question and send it again, or regenerate a reply with another model. Read a reply aloud, or ask with your voice.
- **PDFs.** Drop a PDF to send its text, page by page.
- **Code mode.** Gatita can ask before each command, with "Always allow" for a project. A reply's file changes can be undone. `batch` makes up to 10 tool calls in one step, `read_files` takes folders and patterns, and `web_fetch` takes up to 5 addresses.
- **MCP servers.** Add local or remote MCP servers in Settings, MCP Servers, or import them from Claude Desktop. Each tool call asks first unless you trust the server.
- **Shortcuts, Siri, and Services.** "Ask Gatita" works in Shortcuts and Siri, and in the Mac's Services menu for selected text.
- **Scheduled prompts (Mac).** Run a prompt every hour, every day, on weekdays, or every week, and get a notification with the answer.
- **Notifications.** Gatita tells you when a reply finishes, asks a question, or fails while you're in another app, and when a background command ends. They replace the finished-reply badge.
- **Look.** Buttons, dialogs, menus, and tabs in Gatita's style. The Chat menu has shortcuts, Rename, Export as Markdown, and Delete all chats. Your own skills in Settings, My skills.
- **Fixes.** Prices such as "$5" stay text next to math. Escape closes only the dialog or menu on top, and no longer stops a reply. Quitting stops running background commands. `web_fetch` keeps an address with commas whole. `read_files` reads paths with brackets, skips hidden files unless asked, and says when a pattern is broken. A Mac with no microphone says so instead of crashing.

## 0.0.6 alpha

Connectors, skills, better tool calling, and a "No internet access" error.

- **Connectors.** Seven new ones that need no key or sign-in and work on every device: Weather, Wikipedia, Dictionary, Currency rates, Packages (npm, PyPI, crates.io, and Go), Stack Overflow, and Public GitHub repos. Each stays off until you turn it on or type `!name`. The Shop now lists every connector, Calendar included.
- **Skills.** Ten new: Debug, Refactor, Commit message, Write docs, Security check, Check dependencies, Research, Summarize, Study helper, and Writing help.
- **No internet.** A banner shows while the device is offline, and a message sent then gets "Error: No internet access." What you typed stays in the prompt box.
- **Rate limits.** When the API's rate limit is reached, the reply waits as long as the server asks, with a countdown, and tries again instead of failing.
- **Tool calling.** Tools run off the main thread, so the window no longer freezes while a command runs. Broken tool calls are repaired (line breaks inside text, code fences, trailing commas, and the OpenAI shape), and errors say what would work. New `read_files` and `find_files` tools; `search_text` can ignore case and stay in one folder. A reply can make up to 40 rounds of tool calls. A reply that ends early is asked to go on, then says why it ended.
- **Replies.** Markdown tables, and bar, line, and pie charts with the Charts skill. Under each reply: its token count, buttons to copy, fork, pin, and reply, and the time. `/usage` shows the totals. A reply stops the moment a control token shows up.
- **Settings.** Your own instructions, read before every reply. Transcript view: Normal, Thinking, or Verbose.
- **Mac.** The Settings and Shop sheets have a Done button. In Code mode, a bar above the prompt shows the folder, the git worktree and branch, and running background tasks.
- **Fixes.** `/usage` in an empty chat no longer saves an empty chat. A message refused for a missing API key keeps its text. `task_status` waits for a running task, so Gatita no longer polls it in a loop.

## 0.0.5 alpha

Pairing codes, a PC tab, and connection status.

- **PC tab.** On iPhone and iPad, the PC tab sends its chats to your paired Mac, which answers with its own key and no project tools. Its chats are kept apart from the Chat tab's.
- **Connection status.** The chat says whether you are connected to your Mac. The Mac says when a device connects.
- **Pairing codes.** The Mac makes a new six-digit code each time you allow devices, and the phone types it in. The code stops working when the time is up.
- **Fixes.** A code with spaces around it now pairs. Pressing Connect with no code says what to do.
- **Removed.** The "Send my chats to my Mac" switch. The PC tab replaces it.
- **Web.** `web_curl` sends a raw GET request for APIs and JSON. It shows the status, the content type, and the body as text. The same public https rules apply as for pages.

## 0.0.4 alpha

Pairing, the Settings menu, and iPad layout.

- **Pairing.** On the Mac, set a code in Settings, then press "Allow devices for 5 minutes". A phone or iPad with the same code can pair while that window is open. Pairing works on the same Wi-Fi only.
- **Settings menu.** Settings is a menu with a page for each part: Account, Usage, Pairing, Plugins, Skills, Connectors, About, and Logs. Descriptions wrap instead of being cut off.
- **iPhone and iPad.** The starter prompts sit in a centered column, and their text wraps instead of running off the screen.
- **Chat on the Mac.** Chat no longer has the failure-report or question tools. Connectors you turn on still run, so Web pages can read a public page for research.
- **Prompt rail.** Click a line on the right edge of a conversation to jump to that prompt. The jump and the highlight are animated.

## 0.0.3 alpha

Fixes for iPhone and iPad.

- **Opens on a chat.** The iPhone app opens on a new chat with the input bar. The chats button in the top-left opens the chat list as a sheet.
- **New chat works on iPhone.** New chat and picking a chat both open that chat.
- **Starter prompts** scroll sideways on one line instead of wrapping.

## 0.0.2 alpha

Updates and fixes since 0.0.1.

- **Chat and Code.** Two modes, switched from the top of the sidebar. A chat stays in the mode it was started in. Code works on a project; Chat is regular chat.
- **Code tools.** Edits show as diffs in the chat. The Activity panel lists tool calls, background tasks, subagents, and changed files.
- **Background work.** Commands can run in the background and be checked or stopped later. Subagents work on one task in a read-only run.
- **Pictures.** Attach PNG, JPEG, GIF, or WebP pictures up to 4 MB. On the Mac, a long paste becomes a Markdown attachment.
- **Safety and errors.** Local safety rules refuse some requests before they reach the model. Errors show as red messages, with a reason only when the server gives one.
- **Mac.** One window with a sidebar, no title bar strip, and a Keep the Mac awake option.
- **Fixes.** A saved chat keeps its generated title. A garbled reply shows a message instead of disappearing.

## 0.0.1 alpha

First alpha. Expect rough edges.

- Mac host with project tools: read and search files, edit when turned on, allowed commands in a sandbox, GitHub reads, pull requests, calendar reads, web reads.
- iPhone, iPad, and Vision Pro as question-only hosts: no project folder, edits, commands, or GitHub.
- Streamed replies, with pieces sent to clients as they are written.
- Saved chats with titles, skills, plugins, connectors, and the shop.
- Unit tests (`GatitaTests`).
