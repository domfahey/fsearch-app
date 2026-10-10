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
    private let defaults: UserDefaults
    private let exists: (String) -> Bool
    private let now: () -> Date
    private let key = "recentPaths"
    private let lock = NSLock()
    /// The stored list the last check ran on, its result, and when (guarded by `lock`).
    private var cache: (stored: [String], paths: [String], at: Date)?

    /// Creates the store.
    ///
    /// - Parameters:
    ///   - defaults: Where the list is kept.
    ///   - exists: Whether a path still exists; vanished files are hidden.
    ///   - now: The clock that ages the existence check (``recheckAfter``).
    public init(
        defaults: UserDefaults, exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.exists = exists
        self.now = now
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
    public var paths: [String] {
        let stored = defaults.stringArray(forKey: key) ?? [], t = now()
        if let c = lock.withLock({ cache }), c.stored == stored, t.timeIntervalSince(c.at) < Self.recheckAfter, t >= c.at {
            return c.paths
        }
        var found: [String] = []
        // Stop at `limit`: older entries are only checked when newer ones are gone.
        for p in stored where found.count < Self.limit && exists(p) { found.append(p) }
        lock.withLock { cache = (stored, found, t) }
        return found
    }
}
