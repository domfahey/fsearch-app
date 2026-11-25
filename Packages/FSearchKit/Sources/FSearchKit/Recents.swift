import Foundation
import Synchronization

/// The last files opened from the panel, shown when the query is empty.
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe, and the existence
/// cache is guarded by a `Mutex`.
public final class Recents: @unchecked Sendable {
    /// The most recents shown.
    public static let limit = 8
    /// How long a check of which recents still exist is reused. The panel
    /// reads `entries` on every redraw, and each check can block on a slow
    /// network mount.
    static let recheckAfter: TimeInterval = 2
    /// A recent that still exists.
    public struct Entry: Equatable, Sendable {
        /// The file's path.
        public let path: String
        /// Whether it is a folder (packages included).
        public let isDirectory: Bool
        /// Creates an entry.
        public init(path: String, isDirectory: Bool) { (self.path, self.isDirectory) = (path, isDirectory) }
    }

    private struct CacheState {
        var cache: (stored: [String], entries: [Entry], at: Date)?
        var generation: UInt64 = 0
    }

    private let defaults: UserDefaults
    /// nil if a path is gone, else whether it is a folder.
    private let probe: @Sendable (String) -> Bool?
    private let now: @Sendable () -> Date
    private let key = "recentPaths"
    private let state = Mutex(CacheState())

    /// Creates the store.
    ///
    /// - Parameters:
    ///   - defaults: Where the list is kept.
    ///   - probe: nil if a path is gone (vanished files are hidden), else whether it is a folder.
    ///   - now: The clock that ages the existence check (``recheckAfter``).
    public init(
        defaults: UserDefaults, probe: @escaping @Sendable (String) -> Bool? = Recents.onDisk,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.probe = probe
        self.now = now
    }

    /// Creates the store with an existence check that knows no folders.
    ///
    /// - Parameters:
    ///   - defaults: Where the list is kept.
    ///   - exists: Whether a path still exists; vanished files are hidden.
    ///   - now: The clock that ages the existence check (``recheckAfter``).
    public convenience init(
        defaults: UserDefaults, exists: @escaping @Sendable (String) -> Bool, now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(defaults: defaults, probe: { exists($0) ? false : nil }, now: now)
    }

    /// The real probe: one `stat` for whether the path exists and is a folder.
    public static func onDisk(_ path: String) -> Bool? {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) ? isDir.boolValue : nil
    }

    /// Records that a file was opened, making it the newest.
    ///
    /// - Parameter path: The file's path.
    public func opened(_ path: String) {
        state.withLock { s in
            var list = defaults.stringArray(forKey: key) ?? []
            list.removeAll { $0 == path }
            list.insert(path, at: 0)
            // Keep up to 16 so files that have since gone still leave 8 to show.
            defaults.set(Array(list.prefix(Self.limit * 2)), forKey: key)
            s.cache = nil
            s.generation &+= 1
        }
    }

    /// Check the files again on the next read (one was trashed, or the panel opened).
    public func invalidate() {
        state.withLock { s in
            s.cache = nil
            s.generation &+= 1
        }
    }

    /// Up to ``limit`` recents that still exist, newest first. The existence
    /// check is reused until the list changes, ``invalidate()`` is called, or
    /// ``recheckAfter`` passes.
    public var entries: [Entry] {
        let t = now()
        let snapshot: (stored: [String], gen: UInt64, cached: [Entry]?) = state.withLock { s in
            let stored = defaults.stringArray(forKey: key) ?? []
            if let c = s.cache, c.stored == stored, t.timeIntervalSince(c.at) < Self.recheckAfter, t >= c.at {
                return (stored, s.generation, c.entries)
            }
            return (stored, s.generation, nil)
        }
        if let cached = snapshot.cached { return cached }
        var found: [Entry] = []
        // Stop at `limit`: older entries are only checked when newer ones are gone.
        for p in snapshot.stored {
            if found.count == Self.limit { break }
            if let isDir = probe(p) { found.append(Entry(path: p, isDirectory: isDir)) }
        }
        state.withLock { s in
            if s.generation == snapshot.gen { s.cache = (snapshot.stored, found, t) }
        }
        return found
    }

    /// The paths of ``entries``.
    public var paths: [String] { entries.map(\.path) }
}
