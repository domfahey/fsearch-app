import AppKit
import UniformTypeIdentifiers

/// System file icons, cached by file type, so fast typing doesn't trigger
/// thousands of icon lookups.
@MainActor
final class IconCache {
    /// The one cache.
    static let shared = IconCache()
    private var byType: [String: NSImage] = [:]

    /// Folders (a dotted one like v1.2 too), extensionless files and apps
    /// have their own icons, asked for by path; anything else shares its
    /// extension's cached icon.
    static func usesFileIcon(path: String, isDirectory: Bool) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return isDirectory || ext.isEmpty || ext == "app"
    }

    /// `isDirectory` comes from the search result (the daemon's kind), so no disk access.
    func icon(for path: String, isDirectory: Bool = false) -> NSImage {
        if Self.usesFileIcon(path: path, isDirectory: isDirectory) { return NSWorkspace.shared.icon(forFile: path) }
        let ext = (path as NSString).pathExtension.lowercased()
        if let cached = byType[ext] { return cached }
        let img = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        byType[ext] = img
        return img
    }
}
