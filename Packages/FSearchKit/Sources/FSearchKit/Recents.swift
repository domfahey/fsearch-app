import Foundation

/// The last files opened from the panel, shown when the query is empty.
public final class Recents: @unchecked Sendable {
    public static let limit = 8
    private let defaults: UserDefaults
    private let exists: (String) -> Bool
    private let key = "recentPaths"

    public init(defaults: UserDefaults, exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.defaults = defaults
        self.exists = exists
    }

    public func opened(_ path: String) {
        var list = defaults.stringArray(forKey: key) ?? []
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        // Keep up to 16 so files that have since gone still leave 8 to show.
        defaults.set(Array(list.prefix(Self.limit * 2)), forKey: key)
    }

    public var paths: [String] {
        Array((defaults.stringArray(forKey: key) ?? []).filter(exists).prefix(Self.limit))
    }
}
