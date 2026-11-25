import AppKit
import UniformTypeIdentifiers

/// System file icons, cached by file type and (for folders, apps and extensionless files) by path,
/// with bounded `NSCache` limits so fast typing doesn't trigger thousands of icon lookups or grow without bound.
@MainActor
final class IconCache {
    /// The one cache.
    static let shared = IconCache()
    private let byType = NSCache<NSString, NSImage>()
    private let byPath = NSCache<NSString, NSImage>()

    init(typeLimit: Int = 256, pathLimit: Int = 512) {
        byType.countLimit = typeLimit
        byPath.countLimit = pathLimit
    }

    var typeCountLimit: Int { byType.countLimit }
    var pathCountLimit: Int { byPath.countLimit }

    /// Folders (a dotted one like v1.2 too), extensionless files and apps
    /// have their own icons, asked for by path; anything else shares its
    /// extension's cached icon.
    static func usesFileIcon(path: String, isDirectory: Bool) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return isDirectory || ext.isEmpty || ext == "app"
    }

    /// `isDirectory` comes from the search result (the daemon's kind), so no disk access.
    func icon(for path: String, isDirectory: Bool = false) -> NSImage {
        if Self.usesFileIcon(path: path, isDirectory: isDirectory) {
            let key = path as NSString
            if let cached = byPath.object(forKey: key) { return cached }
            let img = NSWorkspace.shared.icon(forFile: path)
            byPath.setObject(img, forKey: key)
            return img
        }
        let ext = (path as NSString).pathExtension.lowercased() as NSString
        if let cached = byType.object(forKey: ext) { return cached }
        let img = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext as String) ?? .data)
        byType.setObject(img, forKey: ext)
        return img
    }
}
