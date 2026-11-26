# 0014. The `fsearch://` URL scheme opens the panel and never acts

Date: 2026-11-24
Status: Accepted

## Context

Other apps, Shortcuts and scripts want to hand FSearch a query. Any app or web page can open a URL, so a URL scheme is an input from outside the app. The app is a menu-bar extra (`LSUIElement`) with no window to receive the URL, and it runs with Full Disk Access.

## Considered options

- A scheme with action verbs (open, reveal, delete a path). It is powerful, but any page could trigger a file action.
- A scheme that only pre-fills a search. This is the choice below.
- No scheme. Callers would have to drive the UI or use the daemon directly.

## Decision

Register `fsearch` in `App/Resources/Info.plist` (`CFBundleURLTypes`, role Viewer). `SearchURL.parse` in FSearchKit accepts only `fsearch://search`, with an optional `q` and `mode` (`names`, `content` or `symbols`):

- It rejects other schemes and hosts, any path other than empty or `/`, userinfo or a port, and an unknown `mode`. Unknown query items are ignored.
- It turns line breaks and tabs into spaces, drops control characters, and caps the query at 1000 Unicode scalars at a grapheme boundary (`SearchURL.sanitize`).
- `AppDelegate.application(_:open:)` takes the last valid URL and calls `PanelHost.show(app:search:)`. A URL that arrives during cold launch is held until startup finishes. The panel opens with the query and mode filled in, and a visible panel updates in place.

A URL never searches silently and never runs a file action. The person sees the query and chooses what to do. Debug windows are marked `.handlesExternalEvents(matching: [])` so a URL cannot open them.

## Consequences

- A hostile link can at most put text in the search box.
- Callers that want results without the panel use the [Search Files action](0015-app-intents-search-files-action.md) instead.
- The scheme is documented in the [URL scheme reference](../reference/url-scheme.md).
- Adding a host or action later means a new decision, since the "never acts" rule is what makes the scheme safe to expose.
