import AppKit
import FSearchKit
import Foundation

/// Multi-select file actions for the Everything-style search window, routed through ``FileActions`` seams.
@MainActor
enum SearchWindowActions {
    /// Opens each selected row, respecting ``FileActions/revealsOnReturn(_:editor:)`` for launchables
    /// and recording non-launchable opened files in Recents.
    static func openSelected(
        _ rows: [SearchWindowRow], app: AppState, onError: @escaping @MainActor (String) -> Void
    ) {
        guard !rows.isEmpty else { return }
        for row in rows {
            if FileActions.revealsOnReturn(row.item, editor: app.editor) {
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
        guard !rows.isEmpty else { return false }
        var existing: [URL] = []
        var missingReported = false
        for row in rows {
            if FileActions.workspace.fileInfo(atPath: row.path) != nil {
                existing.append(FileActions.url(row.path))
            } else if !missingReported {
                missingReported = true
                onError(FileActions.missingMessage(row.path))
            }
        }
        guard !existing.isEmpty else { return false }
        FileActions.workspace.activateFileViewerSelecting(existing)
        return true
    }

    /// Copies the raw paths of all selected items (newline-separated) to ``FileActions/pasteboard``.
    static func copyPaths(_ rows: [SearchWindowRow]) {
        guard !rows.isEmpty else { return }
        FileActions.copyPath(rows.map(\.path).joined(separator: "\n"))
    }

    /// Copies all existing selected file URLs to ``FileActions/pasteboard`` so Finder can paste them.
    @discardableResult
    static func copyFiles(
        _ rows: [SearchWindowRow], onError: @MainActor (String) -> Void
    ) -> Bool {
        guard !rows.isEmpty else { return false }
        var urls: [NSURL] = []
        var missingReported = false
        for row in rows {
            if FileActions.workspace.fileInfo(atPath: row.path) != nil {
                urls.append(FileActions.url(row.path) as NSURL)
            } else if !missingReported {
                missingReported = true
                onError(FileActions.missingMessage(row.path))
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

    /// Moves all selected rows to the Trash, updates Recents, and invokes `refresh` if any succeeded.
    static func trashSelected(
        _ rows: [SearchWindowRow], app: AppState, onError: @MainActor (String) -> Void,
        refresh: () async -> Void
    ) async {
        guard !rows.isEmpty else { return }
        var trashedAny = false
        for row in rows {
            do {
                try FileActions.trash(row.path)
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
