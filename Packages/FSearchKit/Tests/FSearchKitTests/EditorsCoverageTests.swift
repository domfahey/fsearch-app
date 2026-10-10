import Foundation
import Testing
@testable import FSearchKit

@Suite struct EditorsCoverageTests {
    @Test func everyEditorHasADistinctBundleIdAndName() {
        let expected: [Editor: (String, String)] = [
            .vscode: ("com.microsoft.VSCode", "Visual Studio Code"),
            .cursor: ("com.todesktop.230313mzl4w4u92", "Cursor"),
            .zed: ("dev.zed.Zed", "Zed"),
            .sublime: ("com.sublimetext.4", "Sublime Text"),
            .bbedit: ("com.barebones.bbedit", "BBEdit"),
            .xcode: ("com.apple.dt.Xcode", "Xcode"),
        ]
        #expect(Editor.allCases.count == expected.count)
        for e in Editor.allCases {
            #expect(e.bundleId == expected[e]?.0)
            #expect(e.displayName == expected[e]?.1)
        }
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

    @Test func lineNumbersAreInterpolatedVerbatim() {
        let app = URL(fileURLWithPath: "/A.app")
        #expect(openAtLine(.vscode, appURL: app, path: "/f", line: 1).arguments == ["-g", "/f:1"])
        #expect(openAtLine(.xcode, appURL: app, path: "/f", line: 99999).arguments == ["-l", "99999", "/f"])
        #expect(openAtLine(.bbedit, appURL: app, path: "/f", line: 0).arguments == ["+0", "/f"])
    }

    @Test func xcodeIgnoresTheAppURL() {
        let a = openAtLine(.xcode, appURL: URL(fileURLWithPath: "/one.app"), path: "/f", line: 2)
        let b = openAtLine(.xcode, appURL: URL(fileURLWithPath: "/two.app"), path: "/f", line: 2)
        #expect(a == b)
    }

    @Test func pathsAreNeverQuotedOrSplit() {
        let tricky = "/tmp/it's \"x\" $HOME; rm -rf *.txt"
        for e in Editor.allCases {
            let c = openAtLine(e, appURL: URL(fileURLWithPath: "/A.app"), path: tricky, line: 5)
            #expect(c.arguments.contains { $0.contains(tricky) }, "\(e) passes the path untouched")
        }
    }

    @Test func installedFollowsDeclaredOrderNotLookupOrder() {
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
