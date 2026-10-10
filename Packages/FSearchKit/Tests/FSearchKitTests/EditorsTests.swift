import Foundation
import Testing
@testable import FSearchKit

@Suite struct EditorsTests {
    let path = "/Users/me/Downloads/🏡 105 25Th Street So, Brigantine.txt"

    /// The path (with spaces and an emoji) is always one argument, never split.
    /// The Zed, Sublime Text and BBEdit CLI paths are UNVERIFIED (not installed
    /// on the dev Mac); see Editors.swift.
    @Test func commandsPerEditor() {
        let app = URL(fileURLWithPath: "/Applications/X.app")
        let want: [Editor: EditorCommand] = [
            .vscode: EditorCommand(executable: "/Applications/X.app/Contents/Resources/app/bin/code", arguments: ["-g", "\(path):12"]),
            .cursor: EditorCommand(executable: "/Applications/X.app/Contents/Resources/app/bin/cursor", arguments: ["-g", "\(path):12"]),
            .zed: EditorCommand(executable: "/Applications/X.app/Contents/MacOS/cli", arguments: ["\(path):12"]),
            .sublime: EditorCommand(executable: "/Applications/X.app/Contents/SharedSupport/bin/subl", arguments: ["\(path):12"]),
            .bbedit: EditorCommand(executable: "/Applications/X.app/Contents/Helpers/bbedit_tool", arguments: ["+12", path]),
            .xcode: EditorCommand(executable: "/usr/bin/xed", arguments: ["-l", "12", path]),
        ]
        #expect(want.count == Editor.allCases.count)
        for e in Editor.allCases {
            #expect(openAtLine(e, appURL: app, path: path, line: 12) == want[e], "\(e)")
        }
    }

    @Test func installedIsOnlyWhatLookupFinds() {
        let found = installedEditors { $0 == Editor.zed.bundleId ? URL(fileURLWithPath: "/Applications/Zed.app") : nil }
        #expect(found.map(\.0) == [.zed])
    }
}
