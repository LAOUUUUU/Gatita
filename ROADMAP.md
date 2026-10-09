# Roadmap

## Platform roles

Gatita has two kinds of device.

- **Host** runs the chat request, waits for Gatita's reply, and runs any tools. Only a host holds the API key.
- **Client** sends the prompt to a host over the local network (MultipeerConnectivity) and shows the reply. A client never calls Gatita and never holds the key.

| Platform | Role | What it can do |
|---|---|---|
| macOS | Host, full | Chat, project files (edits when turned on), allowed commands in the sandbox, GitHub reads, pull requests, calendar reads, web reads, plugins, connectors, the shop |
| iOS and iPadOS | Host, questions only | Chat and web reads. No project files, no edits, no commands, no GitHub, no pull requests |
| visionOS | Host, questions only | Same as iOS and iPadOS |
| tvOS | Client | Sends prompts to a host and shows the replies. Not built yet (see the transport decision) |
| homeOS | Client | Same as tvOS. There is no homeOS SDK in Xcode, so it cannot be built here |
| watchOS | Client | Same as tvOS, with a short reply view. Not built yet (see the transport decision) |

Each platform's rules are in `Shared/Tools/HostPolicy.swift`. The decision record is [docs/decisions/001-question-only-hosts.md](docs/decisions/001-question-only-hosts.md).

## Where things stand

- **Done:** iOS, iPadOS, and visionOS are question-only hosts. Their settings hide the project folder and the GitHub connector. Hosts stream replies to clients in pieces. Calendar reads on the Mac. The tests run from `xcodebuild test`. The docs folder has the architecture and decisions.
- **Not verified yet:** clients and hosts talking to each other across devices, and the calendar permission prompt. Both build, but neither has run on two real devices or with calendar access granted here.
- **Blocked:** tvOS and watchOS clients need a decision on how they reach a host. The installed tvOS and watchOS SDKs have no MultipeerConnectivity. See [docs/decisions/004-tvos-and-watchos-transport.md](docs/decisions/004-tvos-and-watchos-transport.md). homeOS cannot be built without its SDK.

## Next steps, in order

1. **Limit hosts by platform.** Done. iOS, iPadOS, and visionOS have no project folder, edits, or commands, and no GitHub. Decision: [001](docs/decisions/001-question-only-hosts.md).
2. **Make visionOS a host** that answers questions only. Done. It builds with the host screens.
3. **Clients for tvOS, homeOS, and watchOS.** Blocked on a decision: how a client reaches a host without MultipeerConnectivity. Decision: [004](docs/decisions/004-tvos-and-watchos-transport.md). homeOS also needs its SDK.
4. **Stream replies to clients.** Done for the host side. A host sends each piece as Gatita writes it, and the client shows the reply as it grows. Covered by tests; not yet tried between two devices.
5. **Calendar and Gmail connectors.** Calendar is done: it reads events through macOS EventKit, read-only, on the Mac. Gmail is not started: it needs a Google sign-in set up first, which is an account decision.
6. **Tests in the repo.** Done. The tests are an XCTest target, `GatitaTests`, run with `xcodebuild test`. They live in `Tests/GatitaTests`.
7. **A hosted shop, later.** Deferred until there is a catalog that is reviewed and signed. The shop still offers only items bundled with the app. Decision: [003](docs/decisions/003-hosted-shop-deferred.md).
8. **A docs folder** for the architecture and design decisions. Done: [docs/architecture.md](docs/architecture.md) and [docs/decisions](docs/decisions).
