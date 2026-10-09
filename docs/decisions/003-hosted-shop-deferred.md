# 003: A hosted shop waits for a reviewed, signed catalog

**Status:** accepted (deferred)

## Context

The shop offers plugins, skills, and connectors. Today every item is bundled with the app, so nothing is downloaded or run to install it.

A hosted shop would download plugin folders from a server. A plugin can add commands, and commands run on the Mac, so an unreviewed download is a real risk.

## Decision

No download is added until the shop has a catalog that is reviewed and signed, and the app checks the signature before installing anything. The shop stays bundled-only until then.

## Consequences

- Nothing in the app fetches plugins from the network.
- The signing and review process needs its own decision before work starts. It is not built yet.
