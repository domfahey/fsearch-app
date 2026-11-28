import Foundation

/// Files that ↵ would launch rather than open: apps, scripts, installers and
/// internet locations. ↵ reveals these in Finder instead; ⌘K → Open still
/// launches them, as an explicit choice.
public enum Launchable {
    /// Extensions (lowercased) that run something when opened.
    static let extensions: Set<String> = [
        "app", "command", "tool", "terminal", "workflow", "pkg", "mpkg", "scpt", "applescript", "webloc", "inetloc", "fileloc",
        // Installs a configuration profile, pane, screen saver or plugin, or runs an action or shortcut, when opened.
        "mobileconfig", "prefpane", "saver", "qlgenerator", "osax", "action", "shortcut",
        // Runs a Java program or Web Start app; a script bundle; disk images, archives, and internet locations.
        "jar", "jnlp", "scptd", "dmg",
        "sparseimage", "sparsebundle", "iso", "img", "cdr", "xip", "url", "vncloc", "ftploc", "afploc", "mailloc",
    ]

    /// The extension of the last path component, lowercased; "" for none (a leading dot is no extension).
    static func pathExtension(_ path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }

    /// Whether `revealsOnReturn` needs to know about the file itself: only an
    /// extensionless path might be an executable. Anything else is decided by
    /// its name, without touching the disk.
    public static func needsFileCheck(_ path: String) -> Bool { pathExtension(path).isEmpty }

    /// True if ↵ should reveal `path` in Finder instead of opening it. An
    /// extensionless executable file would run in Terminal; a folder never does.
    /// Finder aliases and symlinks to launchable targets also reveal.
    public static func revealsOnReturn(
        path: String, isDirectory: Bool, isExecutable: Bool,
        resolvedPath: String? = nil, isAlias: Bool = false
    ) -> Bool {
        if isAlias { return true }
        let ext = pathExtension(path)
        if extensions.contains(ext) { return true }
        if let resolvedPath, resolvedPath != path {
            let resolvedExt = pathExtension(resolvedPath)
            if extensions.contains(resolvedExt) { return true }
            if resolvedExt.isEmpty && !isDirectory && isExecutable { return true }
        }
        return ext.isEmpty && !isDirectory && isExecutable
    }
}
