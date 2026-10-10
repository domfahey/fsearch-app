import AppKit
import UniformTypeIdentifiers

/// System file icons, cached by file type, so fast typing doesn't trigger
/// thousands of icon lookups.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var byType: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        // Folders and bundles (apps) have their own icons; ask for those directly.
        if ext.isEmpty || ext == "app" { return NSWorkspace.shared.icon(forFile: path) }
        if let cached = byType[ext] { return cached }
        let img = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        byType[ext] = img
        return img
    }
}
