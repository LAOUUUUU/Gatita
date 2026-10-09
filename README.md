# Gatita

A SwiftUI chat app for Gatita's API, for Mac, iPhone, iPad, and Apple Vision Pro. The Mac is the full host, with project tools. iPhone, iPad, and Vision Pro are hosts that answer questions. Other platforms will be clients. See [ROADMAP.md](ROADMAP.md) and [docs/architecture.md](docs/architecture.md).

## What it does

- Chat with Gatita, with streamed replies and visible thinking.
- Saved chats in the sidebar, titled by Gatita. A chat stays in the mode it was started in: Code chats appear only in Code, and Chat chats only in Chat. Each prompt has a line on the right edge of the chat; click one to jump to that prompt.
- A badge in the toolbar and a menu bar item show finished replies and questions from Gatita.
- On a Mac, Gatita can read and search a project folder, run allowed commands in a macOS sandbox, read GitHub pull requests and issues through `gh`, read your calendar events (read-only), and read public web pages.
- On iPhone, iPad, and Vision Pro, Gatita answers questions and reads public web pages. Project files, commands, GitHub, and pull requests are only on the Mac.
- In Code mode, Gatita can run an allowed command in the background and check or stop it later, and start subagents that read the project and answer in parallel. The Activity panel on the right lists tool calls, background tasks, subagents, and changed files.\n- In Code mode, each file change shows as a diff in the chat, with the path, the added and removed line counts, and the changed lines in red and green.
- Pick skills with `/`, project files with `@` (or the `@` button), and plugins or connectors with `!`. The paperclip opens a file picker, and the chosen files show as cards in the prompt box.
- Attach a text file or a picture (PNG, JPEG, GIF, or WebP up to 4 MB) by dropping it on the prompt box or with the paperclip. Each shows as a card inside the box until you send. Pictures are sent to Gatita as images, which the API docs do not describe yet. On a Mac, a paste of 2,000 characters or more becomes a `Pasted text.md` attachment. Files over 2 MB, folders, and files that are not UTF-8 text are refused.
- A Shop with free plugins, skills, and connectors bundled with the app.
- On a Mac, turn on "Keep the Mac awake" in the menu bar or Settings to stop it sleeping on its own while Gatita is open. Closing the lid can still sleep it, and a sleeping Mac cannot run Gatita.
- Logs, analytics, and failure reports stay on your device.

## Build

1. Open `Gatita.xcodeproj` in Xcode.
2. Choose the Gatita scheme and a Mac, iPhone, iPad, or Vision Pro destination.
3. Run.

The Debug build turns off App Sandbox, so the Mac can read your project folder and reach the network. The Release build keeps the sandbox on. It allows outgoing connections (for the API), incoming connections (for talking to your other devices), and calendar access. The Apple Watch source is in the repo but is not built yet.

## Setup

- In Settings, paste your Gatita API key. It is saved in the Keychain, never in a file.
- On a Mac, set the project folder in Settings, for example `~/Documents/Gatita`. Other devices do not have one.
- Other settings are saved in `~/Library/Application Support/Gatita/settings.json`.
- Hosts talk to other devices on your local network. The first time, the system asks for local network access. Allow it, or those devices cannot reach the host.
- Calendar: the first time you ask about your schedule, macOS asks for calendar access. Allow it under Privacy & Security, Calendars.

## Plugins

A plugin is a folder with a `plugin.json` in `~/Library/Application Support/Gatita/plugins/`. It can add skills and commands. Commands run in a macOS sandbox with no network. The Shop installs plugins this way.

## Safety

- The API key is never written to the repo or to `settings.json`.
- Edits and commands stay off until you turn them on in Settings, and they only exist on the Mac.
- A message that matches a local safety rule (`Shared/Safety/SafetyFlags.swift`) is refused on the device, and Gatita is never asked. The starting rules cover explosives and malware.
- Connectors only read. Calendar reads events and never changes them.
- Creating a pull request runs git and gh only after you confirm.

## Versions

Gatita is an alpha, version 0.0.1. The version has three numbers, MAJOR.MINOR.PATCH:

- **MAJOR** (first number): a big refactor or a huge update.
- **MINOR** (second number): new models.
- **PATCH** (third number): updates, bug fixes, and small changes.

No number resets. Each one keeps counting up, so after 0.0.2, a release with new models is 0.1.3, and a big refactor after that is 1.2.4.

The version shows in Settings, under About. Each release is listed in [CHANGELOG.md](CHANGELOG.md). When the version changes, set the version in Xcode (MARKETING_VERSION) and add the changelog entry in the same commit. A test fails if the newest changelog entry does not match the app version.

## Tests

Run the unit tests on the Mac:

```bash
xcodebuild -project Gatita.xcodeproj -scheme Gatita -destination 'platform=macOS' test
```

The agent-loop tests start a local mock of the Gatita API from `Tests/MockServer` with `/usr/bin/python3`, on port 8765. Set `MOCK_PORT` to use another port.

## License

MIT. See [LICENSE](LICENSE).
