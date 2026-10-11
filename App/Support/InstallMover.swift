import AppKit
import Foundation
import os

/// Moving the app out of a translocated copy or a disk image into
/// /Applications. A system adapter (Security, the file system, Finder): tests
/// never run it, and it runs only outside test mode, after the user agreed.
@MainActor
enum InstallMover {
    private typealias IsTranslocated =
        @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
    private typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard let h = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY), let s = dlsym(h, name) else {
            return nil
        }
        return unsafeBitCast(s, to: T.self)
    }

    /// SecTranslocateIsTranslocatedURL (looked up at run time: its header isn't public).
    static func isTranslocated(_ url: URL) -> Bool {
        guard let f = symbol("SecTranslocateIsTranslocatedURL", as: IsTranslocated.self) else { return false }
        var result = false
        return f(url as CFURL, &result, nil) && result
    }

    /// Where a translocated app really is (e.g. ~/Downloads/FSearch.app).
    static func originalURL(of url: URL) -> URL {
        guard isTranslocated(url), let f = symbol("SecTranslocateCreateOriginalPathForURL", as: OriginalPath.self),
            let original = f(url as CFURL, nil)
        else { return url }
        return original.takeRetainedValue() as URL
    }

    /// Copies the app to /Applications and opens the copy once this process
    /// has quit (the copy would otherwise see this one running and quit).
    /// If it can't, shows the app and the Applications folder in Finder.
    static func moveToApplications(from bundle: URL) {
        let source = originalURL(of: bundle)
        let dest = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: dest.path) else {
            // Never overwrite: the user replaces an older copy in Finder.
            NSWorkspace.shared.activateFileViewerSelecting([source, dest])
            return
        }
        do {
            try fm.copyItem(at: source, to: dest)
            // Without this, macOS translocates the copy again on its first launch.
            removeQuarantine(dest)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = relaunchArguments(app: dest, waitingFor: ProcessInfo.processInfo.processIdentifier)
            try p.run()
        } catch {
            Log.daemon.error("move to Applications failed: \(error.localizedDescription, privacy: .private)")
            NSWorkspace.shared.activateFileViewerSelecting([source, URL(fileURLWithPath: "/Applications")])
        }
    }

    /// `/bin/sh` arguments that wait for `pid` to exit (polling every 0.1 s,
    /// for at most 30 s), then open `app` with `open`.
    nonisolated static func relaunchArguments(app: URL, waitingFor pid: Int32, open: String = "/usr/bin/open") -> [String] {
        let script = """
            i=0; while kill -0 "$1" 2>/dev/null && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done; exec "$2" "$0"
            """
        return ["-c", script, app.path, String(pid), open]
    }

    private static func removeQuarantine(_ url: URL) {
        removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        guard let items = FileManager.default.enumerator(atPath: url.path) else { return }
        for case let rel as String in items {
            removexattr(url.appendingPathComponent(rel).path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }
}
