# Roadmap

## Platform roles

Gatita has two kinds of device.

- **Host** runs the chat request, waits for Gatita's reply, and runs any tools. Only a host holds the API key.
- **Client** sends the prompt to a host over the local network (MultipeerConnectivity) and shows the reply. A client never calls Gatita and never holds the key.

| Platform | Role | What it can do |
|---|---|---|
| macOS | Host, full | Chat, project files (edits when turned on), allowed commands in the sandbox, GitHub reads, pull requests, web reads, plugins, connectors, the shop |
| iOS and iPadOS | Host, questions only | Chat and web reads. No file changes, no commands, no pull requests |
| visionOS | Host, questions only | Same as iOS and iPadOS |
| tvOS | Client | Sends prompts to a host and shows the replies |
| homeOS | Client | Same as tvOS |
| watchOS | Client | Same as tvOS, with a short reply view |

**Where things stand today:** macOS, iOS, and iPadOS (one build) are hosts with all tools enabled, including on iOS. visionOS runs as a client. The watchOS code is in the repo but not in the build target, and there is no tvOS or homeOS target yet.

## Next steps, in order

1. **Limit hosts by platform.** Turn off file tools, commands, and pull-request creation on iOS, iPadOS, and visionOS. This is the most important step, because it is a safety issue today.
2. **Make visionOS a host** that answers questions only, instead of a client.
3. **Clients for tvOS, homeOS, and watchOS.** Add the targets and the client screens, and send each prompt to a host.
4. **Stream replies to clients.** Hosts send partial text over MultipeerConnectivity. Today a client only gets the final text.
5. **Calendar and Gmail connectors.** Calendar comes first, through macOS EventKit, since it needs no account. Gmail needs a Google sign-in set up first.
6. **Tests in the repo.** Move the test harness into an XCTest target, so anyone can run it.
7. **A hosted shop, later.** Before it offers any download, the shop needs a catalog that is reviewed and signed. Today it only offers items bundled with the app.
8. **A docs folder** for the architecture and design decisions.
