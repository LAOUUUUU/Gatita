# Gatita

A SwiftUI chat app for Gatita's API, for Mac, iPhone, iPad, and Apple Vision Pro. The Mac is the full host, with project tools. iPhone, iPad, and Vision Pro are hosts that answer questions. Other platforms will be clients. See [ROADMAP.md](ROADMAP.md) and [docs/architecture.md](docs/architecture.md).

## What it does

- Chat with Gatita, with streamed replies and visible thinking.
- Saved chats in the sidebar, titled by Gatita. Each prompt has a line on the right edge of the chat; click one to jump to that prompt.
- A badge in the toolbar and a menu bar item show finished replies and questions from Gatita.
- On a Mac, Gatita can read and search a project folder, run allowed commands in a macOS sandbox, read GitHub pull requests and issues through `gh`, read your calendar events (read-only), and read public web pages.
- On iPhone, iPad, and Vision Pro, Gatita answers questions and reads public web pages. Project files, commands, GitHub, and pull requests are only on the Mac.
- Pick skills with `/`, project files with `@`, and plugins or connectors with `!`.
- A Shop with free plugins, skills, and connectors bundled with the app.
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
- Connectors only read. Calendar reads events and never changes them.
- Creating a pull request runs git and gh only after you confirm.

## Tests

Run the unit tests on the Mac:

```bash
xcodebuild -project Gatita.xcodeproj -scheme Gatita -destination 'platform=macOS' test
```

The agent-loop tests start a local mock of the Gatita API from `Tests/MockServer` with `/usr/bin/python3`, on port 8765. Set `MOCK_PORT` to use another port.

## License

MIT. See [LICENSE](LICENSE).
