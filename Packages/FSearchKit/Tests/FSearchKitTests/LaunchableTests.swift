import Foundation
import Testing

@testable import FSearchKit

@Suite struct LaunchableTests {
    @Test func launchableExtensionsReveal() {
        for ext in [
            "app", "command", "tool", "terminal", "workflow", "pkg", "mpkg", "scpt", "applescript", "webloc", "inetloc", "fileloc",
        ] {
            #expect(Launchable.revealsOnReturn(path: "/x/Thing.\(ext)", isDirectory: false, isExecutable: false), "\(ext)")
            #expect(Launchable.revealsOnReturn(path: "/x/THING.\(ext.uppercased())", isDirectory: false, isExecutable: false), "\(ext)")
        }
        // Bundles are folders on disk.
        #expect(Launchable.revealsOnReturn(path: "/Applications/Safari.app", isDirectory: true, isExecutable: true))
        #expect(Launchable.revealsOnReturn(path: "/x/Do It.workflow", isDirectory: true, isExecutable: false))
    }

    @Test func documentsAndFoldersOpen() {
        for p in ["/x/readme.md", "/x/photo.jpg", "/x/main.swift", "/x/script.sh", "/x/a.command.txt", "/x/app"] {
            #expect(!Launchable.revealsOnReturn(path: p, isDirectory: false, isExecutable: false), "\(p)")
        }
        #expect(!Launchable.revealsOnReturn(path: "/x/folder", isDirectory: true, isExecutable: true))
        #expect(!Launchable.revealsOnReturn(path: "/x/v1.2", isDirectory: true, isExecutable: true))
    }

    /// An extensionless executable file would run in Terminal; one with an
    /// extension (a .sh opens in an editor) or a folder would not.
    @Test func extensionlessExecutablesReveal() {
        #expect(Launchable.revealsOnReturn(path: "/usr/local/bin/tool", isDirectory: false, isExecutable: true))
        #expect(!Launchable.revealsOnReturn(path: "/x/build.sh", isDirectory: false, isExecutable: true))
        #expect(!Launchable.revealsOnReturn(path: "/x/LICENSE", isDirectory: false, isExecutable: false))
        #expect(!Launchable.revealsOnReturn(path: "/x/bin", isDirectory: true, isExecutable: true))
        #expect(Launchable.revealsOnReturn(path: "/x/.hidden", isDirectory: false, isExecutable: true))
    }

    /// The extension alone decides, except for extensionless files, which need a stat.
    @Test func onlyExtensionlessPathsNeedTheFileSystem() {
        #expect(Launchable.needsFileCheck("/x/tool"))
        #expect(Launchable.needsFileCheck("/x/.profile"))
        #expect(!Launchable.needsFileCheck("/x/a.txt"))
        #expect(!Launchable.needsFileCheck("/x/A.app"))
    }
}
