import Darwin
import Foundation
import Security

/// Who holds the daemon's socket, read from `<dataDir>/socket.lock`. The
/// daemon writes its pid there (decimal text, no newline) after taking the
/// lock. Only read, never locked: taking the lock, even briefly, could make a
/// daemon starting at that moment give up.
public enum SocketHolder: Equatable, Sendable {
    /// No lock file, no pid, or the pid isn't running: nobody we can name.
    case none
    /// Our bundled helper: inside our app bundle, or signed as our helper.
    case ours
    /// Some other process, e.g. a CLI install's daemon.
    case other

    /// The pid in a socket.lock; pids 0 and 1 are never a daemon.
    public static func pid(fromLock text: String) -> Int32? {
        guard let p = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), p > 1 else { return nil }
        return p
    }

    /// The code-signing identifier release.sh gives the bundled helper.
    public static let helperIdentifier = "com.domfahey.fsearch.daemon"

    /// Where any copy of our helper sits inside its app. After an update
    /// (Sparkle, or Finder replacing the app) the old helper keeps running
    /// from wherever its bundle went: the Trash or a temp folder.
    static let helperSuffix = "/FSearch.app/Contents/Helpers/fsearch"

    /// Classifies a live holder.
    ///
    /// Only our helper's signing identifier, a path inside `bundlePath`, or a path that is an
    /// FSearch.app's helper makes it ``ours``; anything else is ``other``, never taken over.
    ///
    /// - Parameters:
    ///   - pid: The pid in socket.lock.
    ///   - path: The pid's executable, nil when it isn't running (or its file is gone).
    ///   - identifier: The pid's code-signing identifier, if it has one.
    ///   - bundlePath: The app's bundle.
    public static func classify(pid: Int32?, path: String?, identifier: String? = nil, bundlePath: String) -> SocketHolder {
        guard pid != nil else { return .none }
        if identifier == helperIdentifier { return .ours }
        guard let path else { return .none }
        let bundle = bundlePath.hasSuffix("/") ? bundlePath : bundlePath + "/"
        return path.hasPrefix(bundle) || path.hasSuffix(helperSuffix) ? .ours : .other
    }

    /// The running process's executable, or nil if there is no such process.
    public static func executablePath(pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The running process's code-signing identifier, or nil if there is no
    /// such process or it isn't signed.
    public static func signingIdentifier(pid: Int32) -> String? {
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess, let info = info as? [String: Any] else {
            return nil
        }
        return info[kSecCodeInfoIdentifier as String] as? String
    }

    /// The live holder of the socket in `dataDir`, judged against `bundlePath`
    /// (the app's bundle). A few cheap syscalls, fine on the main thread.
    ///
    /// - Parameters:
    ///   - dataDir: The folder holding socket.lock.
    ///   - bundlePath: The app's bundle.
    ///   - path: A pid's executable (tests inject one).
    ///   - identifier: A pid's code-signing identifier (tests inject one).
    public static func read(
        dataDir: URL, bundlePath: String,
        path: (Int32) -> String? = executablePath(pid:),
        identifier: (Int32) -> String? = signingIdentifier(pid:)
    ) -> SocketHolder {
        let text = try? String(contentsOf: dataDir.appendingPathComponent("socket.lock"), encoding: .utf8)
        guard let pid = text.flatMap(pid(fromLock:)) else { return .none }
        return classify(pid: pid, path: path(pid), identifier: identifier(pid), bundlePath: bundlePath)
    }
}
