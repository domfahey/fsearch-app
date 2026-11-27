import Foundation

/// A reusable search configuration (query, mode, match toggles, filter chips, and sort order) shown in the search window sidebar.
public struct SavedSearch: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Stable unique identifier.
    public let id: UUID
    /// Display name shown in the sidebar.
    public var name: String
    /// Raw query string.
    public var query: String
    /// Search mode (names, inside files, or definitions).
    public var mode: SearchMode
    /// Match toggles (match case, whole word, regex, search in path).
    public var options: SearchMatchOptions
    /// Active filter chips.
    public var chips: [SearchFilterChip]
    /// Table sort order.
    public var sort: SearchWindowSort
    /// SF Symbol name shown beside the saved search.
    public var symbol: String
    /// True for built-in presets that cannot be deleted or renamed.
    public var isBuiltIn: Bool

    /// Creates a saved search configuration.
    public init(
        id: UUID = UUID(), name: String, query: String = "", mode: SearchMode = .names,
        options: SearchMatchOptions = SearchMatchOptions(), chips: [SearchFilterChip] = [],
        sort: SearchWindowSort = .defaultSort, symbol: String = "magnifyingglass", isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.mode = mode
        self.options = options
        self.chips = chips
        self.sort = sort
        self.symbol = symbol
        self.isBuiltIn = isBuiltIn
    }

    /// Built-in quick filter presets available in every search window.
    public static var builtInPresets: [SavedSearch] {
        [
            SavedSearch(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: String(localized: "Recent Code", bundle: .module),
                chips: [
                    SearchFilterChip(kind: .type, value: "code", title: String(localized: "Code", bundle: .module)),
                    SearchFilterChip(kind: .modified, value: "<7d", title: String(localized: "Past 7 days", bundle: .module)),
                ],
                sort: SearchWindowSort(column: .modified, direction: .descending),
                symbol: "chevron.left.forwardslash.chevron.right",
                isBuiltIn: true
            ),
            SavedSearch(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: String(localized: "Documents", bundle: .module),
                chips: [
                    SearchFilterChip(kind: .type, value: "doc", title: String(localized: "Documents", bundle: .module))
                ],
                sort: SearchWindowSort(column: .modified, direction: .descending),
                symbol: "doc.text",
                isBuiltIn: true
            ),
            SavedSearch(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: String(localized: "Images", bundle: .module),
                chips: [
                    SearchFilterChip(kind: .type, value: "image", title: String(localized: "Images", bundle: .module))
                ],
                sort: SearchWindowSort(column: .modified, direction: .descending),
                symbol: "photo",
                isBuiltIn: true
            ),
            SavedSearch(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                name: String(localized: "Large Files", bundle: .module),
                chips: [
                    SearchFilterChip(kind: .size, value: ">100mb", title: String(localized: "Over 100 MB", bundle: .module))
                ],
                sort: SearchWindowSort(column: .size, direction: .descending),
                symbol: "externaldrive",
                isBuiltIn: true
            ),
            SavedSearch(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                name: String(localized: "Downloads", bundle: .module),
                chips: [
                    SearchFilterChip(kind: .folder, value: "~/Downloads", title: String(localized: "Downloads", bundle: .module))
                ],
                sort: SearchWindowSort(column: .modified, direction: .descending),
                symbol: "arrow.down.circle",
                isBuiltIn: true
            ),
        ]
    }
}

/// Persists user-created ``SavedSearch`` items in `UserDefaults` as JSON.
public final class SavedSearchStore: @unchecked Sendable {
    /// The `UserDefaults` key storing the JSON-encoded saved searches.
    public static let storageKey = "savedSearches"

    private let defaults: UserDefaults
    private let lock = NSLock()

    /// Creates a store backed by `defaults`.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Loads all user-created saved searches; returns empty when unset or unreadable.
    public func load() -> [SavedSearch] {
        lock.withLock {
            guard let data = defaults.data(forKey: Self.storageKey),
                let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data)
            else { return [] }
            return decoded
        }
    }

    /// Saves `searches` to `UserDefaults`.
    public func save(_ searches: [SavedSearch]) {
        lock.withLock {
            let userOnly = searches.filter { !$0.isBuiltIn }
            guard let data = try? JSONEncoder().encode(userOnly) else { return }
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Appends a new user saved search (trimmed name; ignores blank names) and persists.
    @discardableResult
    public func add(_ search: SavedSearch) -> [SavedSearch] {
        let trimmed = search.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return load() }
        var copy = search
        copy.name = trimmed
        copy.isBuiltIn = false
        var all = load()
        all.append(copy)
        save(all)
        return all
    }

    /// Renames a user saved search by `id` (ignores blank names) and persists.
    @discardableResult
    public func rename(id: UUID, to newName: String) -> [SavedSearch] {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return load() }
        var all = load()
        if let idx = all.firstIndex(where: { $0.id == id }) {
            all[idx].name = trimmed
            save(all)
        }
        return all
    }

    /// Removes the user saved search with `id` and persists.
    @discardableResult
    public func delete(id: UUID) -> [SavedSearch] {
        var all = load()
        all.removeAll { $0.id == id }
        save(all)
        return all
    }

    /// Removes all saved searches from `UserDefaults`.
    public func clear() {
        lock.withLock {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}
