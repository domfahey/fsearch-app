import Foundation

/// Editors that can open a file at a line, for content results.
///
/// Verified on the dev Mac (2026-10-10, read-only: mdfind + ls, nothing launched):
/// - installed, CLI tool present at the path in `openAtLine`: VS Code
///   (`com.microsoft.VSCode`, `Contents/Resources/app/bin/code`), Cursor
///   (`com.todesktop.230313mzl4w4u92`, `Contents/Resources/app/bin/cursor`),
///   Xcode (`com.apple.dt.Xcode`, `/usr/bin/xed`).
/// - not installed, so their CLI paths are UNVERIFIED: Zed (`dev.zed.Zed`,
///   `Contents/MacOS/cli`), Sublime Text (`com.sublimetext.4`,
///   `Contents/SharedSupport/bin/subl`), BBEdit (`com.barebones.bbedit`,
///   `Contents/Helpers/bbedit_tool`).
public enum Editor: String, CaseIterable, Sendable {
    case vscode, cursor, zed, sublime, bbedit, xcode

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

public struct EditorCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
}

/// The command that opens `path` at `line`. Arguments go to the process as
/// an array (never a shell string), so any path needs no quoting.
public func openAtLine(_ e: Editor, appURL: URL, path: String, line: Int) -> EditorCommand {
    let app = appURL.path
    switch e {
    case .vscode: return EditorCommand(executable: app + "/Contents/Resources/app/bin/code", arguments: ["-g", "\(path):\(line)"])
    case .cursor: return EditorCommand(executable: app + "/Contents/Resources/app/bin/cursor", arguments: ["-g", "\(path):\(line)"])
    case .zed: return EditorCommand(executable: app + "/Contents/MacOS/cli", arguments: ["\(path):\(line)"])
    case .sublime: return EditorCommand(executable: app + "/Contents/SharedSupport/bin/subl", arguments: ["\(path):\(line)"])
    case .bbedit: return EditorCommand(executable: app + "/Contents/Helpers/bbedit_tool", arguments: ["+\(line)", path])
    case .xcode: return EditorCommand(executable: "/usr/bin/xed", arguments: ["-l", "\(line)", path])
    }
}

/// Editors present on this Mac. `lookup` maps a bundle id to its app URL
/// (NSWorkspace.urlForApplication(withBundleIdentifier:) in the app).
public func installedEditors(lookup: (String) -> URL?) -> [(Editor, URL)] {
    Editor.allCases.compactMap { e in lookup(e.bundleId).map { (e, $0) } }
}
