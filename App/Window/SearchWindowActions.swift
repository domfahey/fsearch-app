import AppKit
import FSearchKit
import Foundation

/// Multi-select file actions for the Everything-style search window, routed through ``FileActions`` seams.
@MainActor
enum SearchWindowActions {
    /// Returns unique raw file paths from `rows`, preserving first-seen order.
    ///
    /// Content and definition searches can emit multiple rows for the same file (one per matching line);
    /// path-level file operations deduplicate so each file is only acted on once.
    private static func uniquePaths(_ rows: [SearchWindowRow]) -> [String] {
        var seen = Set<String>()
        return rows.compactMap { seen.insert($0.path).inserted ? $0.path : nil }
    }

    /// Opens each selected row, recording opened files in Recents.
    ///
    /// When `respectLaunchableReveal` is `true` (Return and double-click), launchables (apps, scripts,
    /// installers) are revealed in Finder via ``FileActions/revealsOnReturn(_:editor:)``. Explicit
    /// **Open** actions (context menu and preview pane) pass `false` so launchables can be opened directly.
    static func openSelected(
        _ rows: [SearchWindowRow], app: AppState, respectLaunchableReveal: Bool = true,
        onError: @escaping @MainActor (String) -> Void
    ) {
        guard !rows.isEmpty else { return }
        for row in rows {
            if respectLaunchableReveal && FileActions.revealsOnReturn(row.item, editor: app.editor) {
                FileActions.reveal(row.path, onError: onError)
            } else if FileActions.open(row.item, editor: app.editor, onError: onError) {
                app.openedRecent(row.path)
            }
        }
    }

    /// Reveals all existing selected items in Finder in one batch; reports the first missing file.
    @discardableResult
    static func revealSelected(
        _ rows: [SearchWindowRow], onError: @MainActor (String) -> Void
    ) -> Bool {
        let paths = uniquePaths(rows)
        guard !paths.isEmpty else { return false }
        var existing: [URL] = []
        var missingReported = false
        for path in paths {
            if FileActions.workspace.fileInfo(atPath: path) != nil {
                existing.append(FileActions.url(path))
            } else if !missingReported {
                missingReported = true
                onError(FileActions.missingMessage(path))
            }
        }
        guard !existing.isEmpty else { return false }
        FileActions.workspace.activateFileViewerSelecting(existing)
        return true
    }

    /// Copies the unique raw paths of all selected items (newline-separated) to ``FileActions/pasteboard``.
    static func copyPaths(_ rows: [SearchWindowRow]) {
        let paths = uniquePaths(rows)
        guard !paths.isEmpty else { return }
        FileActions.copyPath(paths.joined(separator: "\n"))
    }

    /// Copies all existing selected file URLs to ``FileActions/pasteboard`` so Finder can paste them.
    @discardableResult
    static func copyFiles(
        _ rows: [SearchWindowRow], onError: @MainActor (String) -> Void
    ) -> Bool {
        let paths = uniquePaths(rows)
        guard !paths.isEmpty else { return false }
        var urls: [NSURL] = []
        var missingReported = false
        for path in paths {
            if FileActions.workspace.fileInfo(atPath: path) != nil {
                urls.append(FileActions.url(path) as NSURL)
            } else if !missingReported {
                missingReported = true
                onError(FileActions.missingMessage(path))
            }
        }
        guard !urls.isEmpty else { return false }
        FileActions.pasteboard.clearContents()
        FileActions.pasteboard.writeObjects(urls)
        return true
    }

    /// Opens Terminal in the folder containing the first selected row.
    static func openTerminal(_ rows: [SearchWindowRow], onError: @escaping @MainActor (String) -> Void) {
        guard let first = rows.first else { return }
        FileActions.openTerminal(at: first.path, onError: onError)
    }

    /// Toggles the Quick Look panel for the first selected row.
    @discardableResult
    static func toggleQuickLook(_ rows: [SearchWindowRow], onError: @MainActor (String) -> Void) -> Bool {
        guard let first = rows.first else { return false }
        return FileActions.quickLook(first.path, onError: onError)
    }

    /// Moves all unique selected files to the Trash, updates Recents, and invokes `refresh` if any succeeded.
    static func trashSelected(
        _ rows: [SearchWindowRow], app: AppState, onError: @MainActor (String) -> Void,
        refresh: () async -> Void
    ) async {
        let paths = uniquePaths(rows)
        guard !paths.isEmpty else { return }
        var trashedAny = false
        for path in paths {
            do {
                try FileActions.trash(path)
                trashedAny = true
            } catch {
                onError(String(localized: "Couldn't move to Trash: \(error.localizedDescription)"))
            }
        }
        if trashedAny {
            app.recentsChanged()
            await refresh()
        }
    }
}
