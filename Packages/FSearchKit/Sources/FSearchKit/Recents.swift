import Foundation

/// The last files opened from the panel, shown when the query is empty.
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe, and the existence
/// cache is guarded by a lock.
public final class Recents: @unchecked Sendable {
    /// The most recents shown.
    public static let limit = 8
    /// How long a check of which recents still exist is reused. The panel
    /// reads `paths` on every redraw, and each check can block on a slow
    /// network mount.
    public static let recheckAfter: TimeInterval = 2
    /// A recent that still exists.
    public struct Entry: Equatable, Sendable {
        /// The file's path.
        public let path: String
        /// Whether it is a folder (packages included).
        public let isDirectory: Bool
        /// Creates an entry.
        public init(path: String, isDirectory: Bool) { (self.path, self.isDirectory) = (path, isDirectory) }
    }

    private let defaults: UserDefaults
    /// nil if a path is gone, else whether it is a folder.
    private let probe: (String) -> Bool?
    private let now: () -> Date
    private let key = "recentPaths"
    private let lock = NSLock()
    /// The stored list the last check ran on, its result, and when (guarded by `lock`).
    private var cache: (stored: [String], entries: [Entry], at: Date)?

    /// Creates the store.
    ///
    /// - Parameters:
    ///   - defaults: Where the list is kept.
    ///   - probe: nil if a path is gone (vanished files are hidden), else whether it is a folder.
    ///   - now: The clock that ages the existence check (``recheckAfter``).
    public init(defaults: UserDefaults, probe: @escaping (String) -> Bool? = Recents.onDisk, now: @escaping () -> Date = Date.init) {
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
    public convenience init(defaults: UserDefaults, exists: @escaping (String) -> Bool, now: @escaping () -> Date = Date.init) {
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
        var list = defaults.stringArray(forKey: key) ?? []
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        // Keep up to 16 so files that have since gone still leave 8 to show.
        defaults.set(Array(list.prefix(Self.limit * 2)), forKey: key)
        invalidate()
    }

    /// Check the files again on the next read (one was trashed, or the panel opened).
    public func invalidate() { lock.withLock { cache = nil } }

    /// Up to ``limit`` recents that still exist, newest first. The existence
    /// check is reused until the list changes, ``invalidate()`` is called, or
    /// ``recheckAfter`` passes.
    public var entries: [Entry] {
        let stored = defaults.stringArray(forKey: key) ?? [], t = now()
        if let c = lock.withLock({ cache }), c.stored == stored, t.timeIntervalSince(c.at) < Self.recheckAfter, t >= c.at {
            return c.entries
        }
        var found: [Entry] = []
        // Stop at `limit`: older entries are only checked when newer ones are gone.
        for p in stored where found.count < Self.limit {
            if let isDir = probe(p) { found.append(Entry(path: p, isDirectory: isDir)) }
        }
        lock.withLock { cache = (stored, found, t) }
        return found
    }

    /// The paths of ``entries``.
    public var paths: [String] { entries.map(\.path) }
}
