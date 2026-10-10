import Foundation

/// The last files opened from the panel, shown when the query is empty.
///
/// `@unchecked Sendable`: its only state is `UserDefaults`, which is thread-safe.
public final class Recents: @unchecked Sendable {
    /// The most recents shown.
    public static let limit = 8
    private let defaults: UserDefaults
    private let exists: (String) -> Bool
    private let key = "recentPaths"

    /// Creates the store.
    ///
    /// - Parameters:
    ///   - defaults: Where the list is kept.
    ///   - exists: Whether a path still exists; vanished files are hidden.
    public init(defaults: UserDefaults, exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.defaults = defaults
        self.exists = exists
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
    }

    /// Up to ``limit`` recents that still exist, newest first.
    public var paths: [String] {
        Array((defaults.stringArray(forKey: key) ?? []).filter(exists).prefix(Self.limit))
    }
}
