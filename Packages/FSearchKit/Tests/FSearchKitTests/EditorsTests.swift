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
        #expect(Editor.installed { _ in nil }.isEmpty)
        var asked: [String] = []
        let all = Editor.installed { id in
            asked.append(id)
            return URL(fileURLWithPath: "/Applications/\(id).app")
        }
        #expect(all.map(\.0) == Editor.allCases && asked == Editor.allCases.map(\.bundleId))
    }

    @Test func distinctMetadataAndStableRawValues() {
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
        #expect(Editor.allCases.map(\.rawValue) == ["vscode", "cursor", "zed", "sublime", "bbedit", "xcode"])
        #expect(Editor(rawValue: "emacs") == nil)
    }

    /// Shell and URL metacharacters in a path are percent-encoded, and only absolute paths produce a URL.
    @Test func pathsCantBreakOutOfTheURLAndBadLinesClamp() throws {
        let tricky = "/tmp/it's \"x\" $HOME; rm -rf *.txt?a=1&line=99#frag"
        for e in Editor.allCases where e != .xcode {
            let u = try #require(e.openURL(path: tricky, line: 5), "\(e)")
            let c = try #require(URLComponents(url: u, resolvingAgainstBaseURL: false))
            #expect(c.fragment == nil, "\(e)")
            switch e {
            case .sublime, .bbedit:
                #expect(c.queryItems?.count == 2 && c.queryItems?.last?.value == "5", "\(e)")
                #expect(URL(string: c.queryItems?.first?.value ?? "")?.path == tricky, "\(e)")
            default:
                #expect(c.query == nil && c.path == "\(tricky):5", "\(e)")
            }
        }
        for e in Editor.allCases { #expect(e.openURL(path: "rel/a.txt", line: 2) == nil) }
        #expect(Editor.vscode.openURL(path: "/a.txt", line: 0)?.absoluteString == "vscode://file/a.txt:1")
        #expect(Editor.bbedit.openURL(path: "/a.txt", line: -4)?.absoluteString == "x-bbedit://open?url=file%3A%2F%2F%2Fa.txt&line=1")
    }

    /// Every editor must be Apple-anchored and carry its own bundle id as signing
    /// identifier, and each third-party editor's team id.
    @Test func codeRequirementsAnchorAndPinIdentifiers() {
        for e in Editor.allCases {
            #expect(e.codeRequirement.hasPrefix("anchor apple"), "\(e)")
            #expect(e.codeRequirement.contains("identifier \"\(e.bundleId)\""), "\(e)")
        }
        #expect(Editor.vscode.codeRequirement.contains("certificate leaf[subject.OU] = \"UBF8T346G9\""))
        #expect(Editor.cursor.codeRequirement.contains("certificate leaf[subject.OU] = \"VDXQ22DGB9\""))
        #expect(Editor.xcode.codeRequirement == "anchor apple and identifier \"com.apple.dt.Xcode\"")
        #expect(Editor.zed.codeRequirement.contains("certificate leaf[subject.OU] = \"MQ55VZLNZQ\""))
        #expect(Editor.sublime.codeRequirement.contains("certificate leaf[subject.OU] = \"Z6D26JE4Y4\""))
        #expect(Editor.bbedit.codeRequirement.contains("certificate leaf[subject.OU] = \"W52GZAXT98\""))
        // Every third-party editor is pinned to its team; Xcode to Apple itself.
        for e in Editor.allCases where e != .xcode { #expect(e.codeRequirement.contains("subject.OU"), "\(e)") }
    }
}
