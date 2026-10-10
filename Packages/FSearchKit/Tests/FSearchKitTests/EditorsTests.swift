import Foundation
import Testing
@testable import FSearchKit

@Suite struct EditorsTests {
    let path = "/Users/me/Downloads/🏡 105 25Th Street So, Brigantine.txt"

    @Test func commandsPerEditor() {
        let app = URL(fileURLWithPath: "/Applications/X.app")
        #expect(openAtLine(.vscode, appURL: app, path: path, line: 12) == EditorCommand(executable: "/Applications/X.app/Contents/Resources/app/bin/code", arguments: ["-g", "\(path):12"]))
        #expect(openAtLine(.cursor, appURL: app, path: path, line: 12).arguments == ["-g", "\(path):12"])
        #expect(openAtLine(.zed, appURL: app, path: path, line: 12) == EditorCommand(executable: "/Applications/X.app/Contents/MacOS/cli", arguments: ["\(path):12"]))
        #expect(openAtLine(.sublime, appURL: app, path: path, line: 12).arguments == ["\(path):12"])
        #expect(openAtLine(.bbedit, appURL: app, path: path, line: 12).arguments == ["+12", path])
        #expect(openAtLine(.xcode, appURL: app, path: path, line: 12) == EditorCommand(executable: "/usr/bin/xed", arguments: ["-l", "12", path]))
    }

    @Test func pathIsOneArgumentEvenWithSpaces() {
        let c = openAtLine(.bbedit, appURL: URL(fileURLWithPath: "/A.app"), path: path, line: 1)
        #expect(c.arguments.last == path)
    }

    @Test func installedIsOnlyWhatLookupFinds() {
        let found = installedEditors { $0 == Editor.zed.bundleId ? URL(fileURLWithPath: "/Applications/Zed.app") : nil }
        #expect(found.map(\.0) == [.zed])
    }
}
