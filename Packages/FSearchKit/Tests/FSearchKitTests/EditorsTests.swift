import Foundation
import Testing

@testable import FSearchKit

@Suite struct EditorsTests {
    let path = "/Users/me/Downloads/🏡 105 25Th Street So, Brigantine.txt"
    let encoded = "/Users/me/Downloads/%F0%9F%8F%A1%20105%2025Th%20Street%20So%2C%20Brigantine.txt"

    /// Editors open through LaunchServices URLs, never as a child process of
    /// FSearch (which would inherit its Full Disk Access). Xcode has no
    /// documented open-at-line URL, so it gets the file.
    @Test func urlsPerEditor() throws {
        // The file URL, itself percent-encoded once more as a query value.
        let asFileURL = "/Users/me/Downloads/%F0%9F%8F%A1%20105%2025Th%20Street%20So,%20Brigantine.txt"
        let fileURL =
            "file%3A%2F%2F"
            + asFileURL.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: ",", with: "%2C")
        let want: [Editor: String?] = [
            .vscode: "vscode://file\(encoded):12",
            .cursor: "cursor://file\(encoded):12",
            .zed: "zed://file\(encoded):12",
            .sublime: "subl://open?url=\(fileURL)&line=12",
            .bbedit: "x-bbedit://open?url=\(fileURL)&line=12",
            .xcode: nil,
        ]
        #expect(want.count == Editor.allCases.count)
        for e in Editor.allCases {
            #expect(e.openURL(path: path, line: 12)?.absoluteString == want[e]!, "\(e)")
        }
    }

    /// The file URL inside the query decodes back to the path.
    @Test func queryURLDecodesToThePath() throws {
        let u = try #require(Editor.sublime.openURL(path: path, line: 3))
        let items = try #require(URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.map(\.name) == ["url", "line"])
        #expect(URL(string: try #require(items[0].value))?.path == path)
        #expect(items[1].value == "3")
    }

    /// A path-style URL decodes back to "<path>:<line>".
    @Test func pathURLDecodesToThePath() throws {
        let u = try #require(Editor.vscode.openURL(path: path, line: 7))
        #expect(u.host == "file")
        #expect(URLComponents(url: u, resolvingAgainstBaseURL: false)?.path == "\(path):7")
    }

    @Test func installedIsOnlyWhatLookupFinds() {
        let found = Editor.installed { $0 == Editor.zed.bundleId ? URL(fileURLWithPath: "/Applications/Zed.app") : nil }
        #expect(found.map(\.0) == [.zed])
    }
}
