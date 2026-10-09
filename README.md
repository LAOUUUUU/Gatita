# Gatita

A SwiftUI chat app for Gatita's API, for iPhone and Mac.

## What it does

- Chat with Gatita, with streamed replies and visible thinking.
- On a Mac, Gatita can read and search a project folder, run allowed commands in a macOS sandbox, read GitHub pull requests and issues through `gh`, and read public web pages.
- Pick skills with `/`, project files with `@`, and plugins or connectors with `!`.
- A Shop with free plugins, skills, and connectors bundled with the app.
- Logs, analytics, and failure reports stay on your Mac.

## Build

1. Open `Gatita.xcodeproj` in Xcode.
2. Choose the Gatita scheme and a Mac or iPhone destination.
3. Run.

The Debug build turns off App Sandbox, so the Mac can read your project folder and reach the network. The Release build keeps the sandbox on. The Apple Watch source is in the repo but is not built yet.

## Setup

- In Settings, paste your Gatita API key. It is saved in the macOS Keychain, never in a file.
- In Settings, set the project folder, for example `~/Documents/Gatita`.
- Other settings are saved in `~/Library/Application Support/Gatita/settings.json`.

## Plugins

A plugin is a folder with a `plugin.json` in `~/Library/Application Support/Gatita/plugins/`. It can add skills and commands. Commands run in a macOS sandbox with no network. The Shop installs plugins this way.

## Safety

- The API key is never written to the repo or to `settings.json`.
- Edits and commands stay off until you turn them on in Settings.
- Connectors only read.
- Creating a pull request runs git and gh only after you confirm.

## Tests

The test harness is not in this repository yet.

## License

Not chosen yet.
