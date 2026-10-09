# 004: How tvOS and watchOS clients reach a host (open)

**Status:** open, awaiting a decision

## Context

The roadmap has clients send prompts to a host over MultipeerConnectivity. The installed tvOS and watchOS SDKs do not include the MultipeerConnectivity framework, so a tvOS or watchOS client cannot use it.

There is no homeOS SDK in Xcode, so a homeOS build cannot be made here at all.

## Options

1. **Local HTTP to the host.** The host listens on the local network and clients call it with `URLSession`. Works on tvOS. Needs a listener, a pairing step, and authentication, because any device on the network could otherwise send prompts.
2. **Relay through an iPhone.** The watch talks to its paired iPhone with WatchConnectivity, and the iPhone forwards to the host over Multipeer. Works for the watch, but it needs an iPhone nearby, and tvOS still needs option 1.
3. **Bonjour plus WebSocket.** Similar to option 1, with a persistent connection so replies stream.

## Decision needed

Which option to build, and how a client pairs with a host.
