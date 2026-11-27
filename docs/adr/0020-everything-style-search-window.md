# 0020. Everything-style multi-window search browser (v2)

Date: 2026-11-27
Status: Accepted

## Context

FSearch for Mac v1 ships a Raycast-style floating launcher panel (680×460 pt, single selection, 50-result default cap) built for quick jump-to-file lookups. For power-user workflows modeled on voidtools Everything—scanning hundreds of matches across the disk, sorting by size or modification date, toggling match rules without memorizing filter syntax, switching between saved searches, acting on multiple files at once, and previewing files side-by-side—a floating panel is too constrained.

At the same time, the pinned `fsearch` daemon (`d26cf78`) returns top-`k` results sorted by match score and does not yet expose server-side `offset` paging, server-side column sorting, or total match counts beyond `limit`. We want to ship the full desktop search window now without blocking on upstream daemon protocol changes, while keeping a clean seam for server-side paging once upstream adds it.

## Decision

Add a native SwiftUI/AppKit **Search Window** (`SearchWindowManager`, creating independent `NSWindow` instances hosting `SearchWindowView` with cascading frames and `Presentation.inert` test safety) alongside the floating launcher panel, sharing the same daemon and `FSearchKit` core:

1. **Multi-window, per-window state:** Every Search Window owns an independent `SearchWindowModel` (backed by its own `names` and `content` `SearchBackend` connections in live mode, or injected fakes in tests) so multiple windows can stay open simultaneously without cancelling each other's queries or sharing selections.
2. **Pure, testable `FSearchKit` core:** All non-UI window logic lives in `Packages/FSearchKit`:
   - `SearchWindowQuery` (`MatchOptions` for Match Case, Whole Word, Regex, Search in Path; `FilterChip` for clickable `type:`, `ext:`, `kind:`, `in:`, `size:`, and `mtime:` filters; query composition; client-side post-filtering for multi-term match rules; and `PageRequest` carrying `offset`, `limit`, and `sort` ready for future daemon paging).
   - `SearchWindowRow` and `SearchWindowSort` (Name, Folder, Size, Kind, Date Modified, and Relevance, ascending/descending, with deterministic tie-breaking and `DisplaySafe` display values).
   - `SearchWindowModel` (`@MainActor @Observable`, generation-guarded latest-wins searches up to `defaultLimit = 1000`, half-typed filter preservation, debounced refresh, sorting, and status-bar summary formatting).
   - `SavedSearch` and `SavedSearchStore` (`UserDefaults`-backed JSON store with built-in presets and user-created saved searches).
3. **Match toggles compiled cleanly for the pinned daemon:**
   - When all four toggles are off, queries pass through unchanged with `limit: 1000` (overridable by an explicit `limit:` in the query).
   - In **File Names** mode, Match Case (`(?-i)`), Whole Word (`\b(?:…)\b`), Regex, and Search in Path compile to the daemon's `re:` / `path:` regex filters (using Rust `regex` syntax without lookahead), with a deterministic client-side verifier for multi-word queries.
   - In **Inside Files** mode, Match Case, Whole Word, and Regex compile to `GrepMode.regex` with explicit `(?-i)` / `(?i)` and `\b(?:…)\b` wrappers.
4. **Dense sortable table, keyboard-first multi-select, drag-out, and preview pane:**
   - Native macOS SwiftUI `Table` with Name, Folder, Size, Kind, and Date Modified columns (plus matching line detail in Inside Files / Definitions mode), sortable by clicking headers, resizable and reorderable via persisted `TableColumnCustomization`.
   - Multi-select actions (`↵` Open respecting `Launchable.revealsOnReturn` and verified `Editor` signatures, `⌘↵` Reveal all selected in Finder, `⌘C` Copy Path(s), `⌘⇧C` Copy File(s), `⌘Y` Quick Look / toggle preview pane, `⌘⌫` Move to Trash, Open Folder in Terminal, `⌘K` Actions menu) plus drag-and-drop file URLs out of rows.
   - Toggleable right-hand preview pane combining metadata, matching-line highlight for content/definition results, and an embedded `QLPreviewView` (skipped under `Presentation.inert` so unit tests never load Quick Look plugins).
5. **Entry points:** Accessible from the menu bar (**New Search Window…**), the panel's `⌘/` FSearch menu (**Search Window**), the panel's App Commands (`window` / `browser`), and `⌘N` inside any Search Window to open additional windows.

## Consequences

- Power users get an Everything-style multi-window browser immediately on top of the existing `fsearch` daemon, with zero changes to the floating launcher panel's fast 50-result path.
- Results are capped at 1,000 rows per query until upstream `fsearch` adds server-side paging (`offset`, `total_hits`, and sort key); the status bar explicitly notes when the 1,000-result cap is reached so users know to narrow with filters.
- Because `SearchWindowQuery.PageRequest` already carries `offset`, `limit`, and `sort`, wiring future daemon paging will require changes only in `SearchBackend` / `DaemonClient` and `SearchWindowModel`, leaving the table, chips, saved searches, and preview UI untouched.
- Both `FSearchKit` and `AppTests` maintain the 95% line-coverage gate across all new window code, and the unit-test host remains completely inert (no real windows shown, no focus stolen, no Quick Look plugins instantiated).
