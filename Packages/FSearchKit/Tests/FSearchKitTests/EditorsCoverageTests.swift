import Foundation
import Testing
@testable import FSearchKit

@Suite struct EditorsCoverageTests {
    @Test func everyEditorHasADistinctBundleIdAndName() {
        let expected: [Editor: String] = [
            .vscode: "com.microsoft.VSCode",
            .cursor: "com.todesktop.230313mzl4w4u92",
            .zed: "dev.zed.Zed",
            .sublime: "com.sublimetext.4",
            .bbedit: "com.barebones.bbedit",
            .xcode: "com.apple.dt.Xcode",
        ]
        #expect(Editor.allCases.count == expected.count)
        for e in Editor.allCases { #expect(e.bundleId == expected[e]) }
        #expect(Set(Editor.allCases.map(\.bundleId)).count == Editor.allCases.count)
        #expect(Set(Editor.allCases.map(\.displayName)).count == Editor.allCases.count)
    }

    @Test func rawValuesAreStable() {
        #expect(Editor.allCases.map(\.rawValue) == ["vscode", "cursor", "zed", "sublime", "bbedit", "xcode"])
        #expect(Editor(rawValue: "emacs") == nil)
    }

    @Test func appPathWithSpacesStaysOneExecutable() {
        let app = URL(fileURLWithPath: "/Applications/Sublime Text.app")
        let c = openAtLine(.sublime, appURL: app, path: "/a b/c d.txt", line: 3)
        #expect(c.executable == "/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl")
        #expect(c.arguments == ["/a b/c d.txt:3"])
    }

    @Test func pathsAreNeverQuotedOrSplit() {
        let tricky = "/tmp/it's \"x\" $HOME; rm -rf *.txt"
        for e in Editor.allCases {
            let c = openAtLine(e, appURL: URL(fileURLWithPath: "/A.app"), path: tricky, line: 5)
            #expect(c.arguments.contains(tricky) || c.arguments.contains("\(tricky):5"), "\(e) passes the path untouched")
        }
    }

    @Test func everyEditorIsLookedUpOnceInDeclaredOrder() {
        var asked: [String] = []
        let found = installedEditors { id in
            asked.append(id)
            return URL(fileURLWithPath: "/Applications/\(id).app")
        }
        #expect(found.map(\.0) == Editor.allCases)
        #expect(asked == Editor.allCases.map(\.bundleId))
        #expect(found.first?.1.path == "/Applications/com.microsoft.VSCode.app")
    }

    @Test func noneInstalledIsEmpty() {
        #expect(installedEditors { _ in nil }.isEmpty)
    }

    @Test func missingAppsAreSkippedAndOthersKeepOrder() {
        let have: Set<String> = [Editor.xcode.bundleId, Editor.vscode.bundleId]
        let found = installedEditors { have.contains($0) ? URL(fileURLWithPath: "/Applications/\($0).app") : nil }
        #expect(found.map(\.0) == [.vscode, .xcode])
        #expect(found.map(\.1.path) == ["/Applications/com.microsoft.VSCode.app", "/Applications/com.apple.dt.Xcode.app"])
    }
}
