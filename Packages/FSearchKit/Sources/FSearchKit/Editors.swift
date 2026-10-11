import Foundation

/// Editors that can open a file at a line, for content results.
///
/// They are opened through LaunchServices with a URL (or, for Xcode, the
/// file), never by running their command-line tool as a child process: macOS
/// holds the launching app responsible for a child, so the editor, its
/// extensions and its terminals would all run with FSearch's Full Disk Access.
///
/// URL schemes, checked on the dev Mac (2026-10-10, read-only: the apps'
/// Info.plist CFBundleURLTypes, nothing launched): VS Code registers `vscode`,
/// Cursor `cursor`. Xcode registers only an undocumented generic `xcode`
/// scheme, so it opens the file without a line. Zed (`zed`), Sublime Text
/// (`subl`) and BBEdit (`x-bbedit`) are not installed there, so their schemes
/// are from their documentation, UNVERIFIED.
public enum Editor: String, CaseIterable, Sendable {
    /// Visual Studio Code.
    case vscode
    /// Cursor.
    case cursor
    /// Zed.
    case zed
    /// Sublime Text.
    case sublime
    /// BBEdit.
    case bbedit
    /// Xcode.
    case xcode

    /// The app's bundle identifier, used to find it with Launch Services.
    public var bundleId: String {
        switch self {
        case .vscode: "com.microsoft.VSCode"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .zed: "dev.zed.Zed"
        case .sublime: "com.sublimetext.4"
        case .bbedit: "com.barebones.bbedit"
        case .xcode: "com.apple.dt.Xcode"
        }
    }

    /// The name shown in menus.
    public var displayName: String {
        switch self {
        case .vscode: "Visual Studio Code"
        case .cursor: "Cursor"
        case .zed: "Zed"
        case .sublime: "Sublime Text"
        case .bbedit: "BBEdit"
        case .xcode: "Xcode"
        }
    }
}

/// URL-safe characters: everything else in a path is percent-encoded, so no
/// path can end the path part, add a query item or start a fragment.
private let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

private func encode(_ s: String, keeping extra: String = "") -> String {
    s.addingPercentEncoding(withAllowedCharacters: unreserved.union(CharacterSet(charactersIn: extra))) ?? ""
}

/// The URL that opens `path` at `line` in `e`, for LaunchServices to hand to
/// the editor app. Nothing is run as a child process, and every character
/// outside the unreserved set is percent-encoded, so any path is safe.
///
/// - Parameters:
///   - e: The editor to use.
///   - path: The file to open; must be absolute.
///   - line: The 1-based line to jump to; lines below 1 become 1.
/// - Returns: The editor's open-at-line URL (schemes listed in ``Editor``), or
///   nil when the editor has none (Xcode: open the file with it instead) or the
///   path isn't absolute.
public func editorURL(_ e: Editor, path: String, line: Int) -> URL? {
    guard path.hasPrefix("/") else { return nil }
    let line = max(1, line)
    let pathPart = encode(path, keeping: "/") + ":\(line)"
    let fileQuery = "url=" + encode(URL(fileURLWithPath: path).absoluteString) + "&line=\(line)"
    switch e {
    case .vscode: return URL(string: "vscode://file" + pathPart)
    case .cursor: return URL(string: "cursor://file" + pathPart)
    case .zed: return URL(string: "zed://file" + pathPart)
    case .sublime: return URL(string: "subl://open?" + fileQuery)
    case .bbedit: return URL(string: "x-bbedit://open?" + fileQuery)
    case .xcode: return nil
    }
}

/// Editors present on this Mac. `lookup` maps a bundle id to its app URL
/// (NSWorkspace.urlForApplication(withBundleIdentifier:) in the app).
///
/// - Parameter lookup: Finds an app by bundle id, or returns nil when it isn't installed.
/// - Returns: Each installed editor with its app URL, in ``Editor`` declaration order.
public func installedEditors(lookup: (String) -> URL?) -> [(Editor, URL)] {
    Editor.allCases.compactMap { e in lookup(e.bundleId).map { (e, $0) } }
}
