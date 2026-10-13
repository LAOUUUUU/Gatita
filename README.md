# Gatita

A SwiftUI chat app for Gatita's API, for Mac, iPhone, iPad, and Apple Vision Pro. The Mac is the full host, with project tools. iPhone, iPad, and Vision Pro are hosts that answer questions. Other platforms will be clients. See [ROADMAP.md](ROADMAP.md) and [docs/architecture.md](docs/architecture.md).

## What it does

- Chat with Gatita, with streamed replies and visible thinking.
- Saved chats in the sidebar, titled by Gatita. A chat stays in the mode it was started in: Code chats appear only in Code, and Chat chats only in Chat. Each prompt has a line on the right edge of the chat; click one to jump to that prompt.
- A badge in the toolbar and a menu bar item show finished replies and questions from Gatita.
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
- On a Mac, turn on "Keep the Mac awake" in the menu bar or Settings to stop it sleeping on its own while Gatita is open. Closing the lid can still sleep it, and a sleeping Mac cannot run Gatita.
- Pairing: on a Mac, open Settings, then Pairing, and press "Allow devices for 5 minutes". The Mac shows a new code. On the phone or iPad, type that code, pick the Mac under Nearby, and connect. The PC tab on the phone or iPad sends its chats to the paired Mac, which answers with its own key and no project tools. The chat says whether it is connected. The code stops working when the time is up. Pairing works only on the same local network, and only while the Mac allows it.
- Replies show Markdown tables. With the Charts skill (pick it with `/`), Gatita draws bar, line, and pie charts from a `chart` block of JSON with a `type`, a `title`, and up to 50 `points`, each a label and a number. A block that isn't valid chart data stays as code.
- Transcript view: Normal shows only the text Gatita writes, Thinking adds its thinking and tool calls folded, and Verbose shows everything open. Choose it from the menu in the Mac chat header, or in Settings.
- Under each reply: its token count (estimated at about four characters a token, and marked as an estimate, when the server reports none), buttons to copy, fork the chat from there, pin, or reply with a quote, and the time. Type `/usage` for the totals.
- Settings, then Instructions, holds your own instructions, which Gatita reads before every reply.
- In Code mode on a Mac, a bar above the prompt shows the project folder, whether it runs locally, and the git worktree and branch (switch worktrees from its menu). A running background task gets a stop button there.
- Gatita stops a reply the moment a control token such as `<|close|>` shows up in it.
- A reply that ends for no good reason is not left hanging. If nothing was written, the length limit cut it off, a tool call was cut off or its closing tag was missing, or it ended in a colon with no tool call, Gatita asks the model to go on, up to twice, and then says why the reply ended.
- `read_files` reads up to 20 project files in one call and returns them as one Markdown document, each under its path, so the model needs fewer tool calls. `find_files` finds files by part of their name, and `search_text` can ignore case and stay in one folder.
- Tool calls forgive the model's usual slips: raw line breaks inside a text, a code fence around the JSON, trailing commas, and the OpenAI shape `{"name": ..., "arguments": {...}}`. Arguments can be text, numbers, or lists. When a call still goes wrong, the error says how to fix it: the tools that exist, the commands that are allowed, or the files with that name. The same call twice in a row is pointed out to the model. Tools run off the main thread, so a long command never freezes the window. One reply can make up to 40 rounds of tool calls.
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
- Connectors only read. Calendar reads events and never changes them. The public connectors send only the words of the request (a place, a search, a package name) to the one service named, with a User-Agent that names Gatita.
- Creating a pull request runs git and gh only after you confirm.

## Versions

Gatita is an alpha, version 0.0.6. The version has three numbers, MAJOR.MINOR.PATCH:

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

## License

MIT. See [LICENSE](LICENSE).
