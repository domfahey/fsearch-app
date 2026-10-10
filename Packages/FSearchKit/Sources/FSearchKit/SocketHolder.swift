import Darwin
import Foundation

/// Who holds the daemon's socket, read from `<dataDir>/socket.lock`. The
/// daemon writes its pid there (decimal text, no newline) after taking the
/// lock. Only read, never locked: taking the lock, even briefly, could make a
/// daemon starting at that moment give up.
public enum SocketHolder: Equatable, Sendable {
    /// No lock file, no pid, or the pid isn't running: nobody we can name.
    case none
    /// A process inside our app bundle (the bundled helper).
    case ours
    /// Some other process, e.g. a CLI install's daemon.
    case other

    /// The pid in a socket.lock; pids 0 and 1 are never a daemon.
    public static func pid(fromLock text: String) -> Int32? {
        guard let p = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), p > 1 else { return nil }
        return p
    }

    /// `path` is the pid's executable, nil when it isn't running.
    public static func classify(pid: Int32?, path: String?, bundlePath: String) -> SocketHolder {
        guard pid != nil, let path else { return .none }
        let bundle = bundlePath.hasSuffix("/") ? bundlePath : bundlePath + "/"
        return path.hasPrefix(bundle) ? .ours : .other
    }

    /// The running process's executable, or nil if there is no such process.
    public static func executablePath(pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The live holder of the socket in `dataDir`, judged against `bundlePath`
    /// (the app's bundle). Two cheap syscalls, fine on the main thread.
    public static func read(dataDir: URL, bundlePath: String) -> SocketHolder {
        let text = try? String(contentsOf: dataDir.appendingPathComponent("socket.lock"), encoding: .utf8)
        let pid = text.flatMap(pid(fromLock:))
        return classify(pid: pid, path: pid.flatMap(executablePath(pid:)), bundlePath: bundlePath)
    }
}
