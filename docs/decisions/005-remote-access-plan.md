# 005: Chats from outside the local network (plan, not built)

**Status:** plan only. Nothing here is built.

## Problem

Paired devices find each other over the local network with MultipeerConnectivity. A phone on mobile data, or on a different Wi-Fi, cannot find the Mac, so it cannot send chats to it.

## Goal

A paired phone or iPad reaches its Mac from anywhere, through a domain, with the same rules as the local network: the pairing code must match, pairing must be allowed on the Mac, and the Mac answers with its own key and no project tools.

## Options

1. **Relay on a domain.** The Mac and the phone each keep an outbound connection to a relay server at a domain, such as `relay.gatita.tech`. The relay passes chats between them. The Mac never opens a port to the internet, and the phone needs no address for the Mac. The relay sees the chat text, so it must be run by the user or be encrypted end to end.
2. **Private network overlay.** Tailscale or a similar service gives both devices a private address. Simple to run, but each device needs that app and an account on it.
3. **Tunnel to the Mac.** A tunnel, such as Cloudflare Tunnel, gives the Mac's local server a public domain. It needs an HTTP server on the Mac, and the Mac then accepts traffic from the internet, so it needs authentication on every request.

## Recommendation

Option 1, a small relay on a domain, using WebSockets, with TLS. Each device signs in with a token it got while pairing on the local network, so the relay knows which phone may talk to which Mac. Keep the pairing code for the first pairing, then use the token.

## Rules to keep whatever the option

- Pairing starts on the local network and stays allowed only for a short time, as now.
- The Mac answers with its own key and no project tools, as now.
- Chats are not stored by the relay. Only the pairing tokens are.
- The relay can be turned off and each device can forget a Mac at any time.

## Open questions

- Who runs the relay: the user, or Gatita?
- Is end-to-end encryption needed, so the relay cannot read chats?
- Does the Gatita API allow the relay's traffic under its terms?
