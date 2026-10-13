# 007: Connectors for free public services, with no keys

**Status:** accepted (2026-10-13)

## Context

Gatita's connectors read the project's GitHub repo, the Mac's calendar, and public web pages. Users asked for more: weather, Wikipedia, a dictionary, exchange rates, and things that help with code. iPhone and iPad can't use the Mac-only connectors, and the model guesses package versions it should check.

Many good sources are free and need no key. A key or a sign-in would mean storing a secret per service and building a sign-in flow for each.

## Decision

Add seven connectors that call free public APIs with no key or sign-in:

| Connector | Service | Limits |
|---|---|---|
| `weather` | Open-Meteo geocoding and forecast | free for non-commercial use |
| `wikipedia` | Wikimedia REST (search, page summary) | asks for a User-Agent with contact details |
| `dictionary` | dictionaryapi.dev | English only |
| `currency` | frankfurter.dev (European Central Bank rates) | about 30 currencies, working days |
| `packages` | npm registry, PyPI, crates.io, Go module proxy | crates.io asks for a User-Agent |
| `stackoverflow` | Stack Exchange API | about 300 requests a day per address without a key |
| `repos` | GitHub REST, unauthenticated | 60 requests an hour per address |

Rules for all of them:

- Each is off until the user turns it on in Settings or types `!name`, like the other connectors. They run in Chat and Code, on every device.
- They only read, over https, and send only the words of the request to the one service.
- Every request carries `User-Agent: Gatita/<version> (https://github.com/LAOUUUUU/Gatita)`.
- Addresses and text are built by pure functions tested with saved answers. `LiveConnectorTests` checks the real services when `GATITA_LIVE_TESTS=1`.
- Answers that come with a license (Wikipedia, Stack Overflow) carry their link, so the model can credit the source.

## Consequences

- No secrets to store, and no new dependencies: everything is `URLSession` and `JSONSerialization`.
- A service can change its answers or limits without notice. The live tests are how that gets noticed.
- Web search is still missing. It needs a paid or self-hosted service, and waits on the Gatita API's owner.
