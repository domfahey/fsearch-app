import AppKit
import FSearchKit

/// Stubs: Task 11 replaces these with the real implementations.
@MainActor
enum FileActions {
    static func open(_ item: ResultItem, editor: Editor?) {}
    static func reveal(_ path: String) {}
    static func quickLook(_ path: String) {}
    static func copyPath(_ path: String) {}
}

@MainActor
enum ActionsMenu {
    static func show(for item: ResultItem, in panel: NSPanel?, app: AppState) {}
}
