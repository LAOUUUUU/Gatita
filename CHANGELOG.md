# Changelog

Gatita uses three numbers, MAJOR.MINOR.PATCH, plus a channel while it is not final:

- **MAJOR** (first number): a big refactor or a huge update.
- **MINOR** (second number): new models.
- **PATCH** (third number): updates, bug fixes, and small changes.

No number resets. Each one keeps counting up, so after 0.0.2, a release with new models is 0.1.3, and a big refactor after that is 1.2.4.

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
