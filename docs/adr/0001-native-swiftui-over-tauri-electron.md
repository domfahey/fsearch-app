# 0001. Native SwiftUI over Tauri or Electron

Date: 2026-10-10
Status: Accepted

## Context

The app is a launcher. It must open instantly from a hotkey, take keyboard focus without activating a window the wrong way, look translucent like macOS, show Quick Look, and let you drag files out of a result row. A launcher feels good or bad on exactly these details.

Three ways to build it were considered: a native app, Tauri, and Electron.

## Decision

Build a native app with SwiftUI, and use AppKit where SwiftUI cannot do the job: the floating panel, the global hotkey, Quick Look and drag and drop.

The search engine stays separate. It is the existing fsearch daemon, reached over its JSON-lines socket (see [ADR 0002](0002-bundle-the-fsearch-daemon-via-smappservice.md)).

The app targets macOS 14 and later, on Apple silicon and Intel.

## Consequences

- Panel focus, translucency, Quick Look and dragging files out work as macOS users expect.
- Startup is fast and memory use is small.
- The app runs only on macOS. That is acceptable: it is a Mac app by name and purpose.
- Parts that need AppKit add some code beside the SwiftUI views.
- Tauri was rejected because a web UI is weakest in exactly those native areas. Electron was rejected for slow start and heavy memory.
