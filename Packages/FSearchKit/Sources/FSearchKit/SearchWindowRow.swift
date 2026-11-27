import Foundation

/// Sortable columns in the Everything-style search window table.
public enum SearchWindowColumn: String, Codable, CaseIterable, Hashable, Sendable {
    /// Daemon match score (highest first by default).
    case relevance
    /// File or folder name.
    case name
    /// Parent folder path.
    case folder
    /// File size in bytes.
    case size
    /// File kind / type label.
    case kind
    /// Last modification timestamp.
    case modified
}

/// Sort direction for a table column.
public enum SortDirection: String, Codable, Hashable, Sendable {
    /// Smallest / A-to-Z / oldest first.
    case ascending
    /// Largest / Z-to-A / newest first.
    case descending

    /// Flips between ascending and descending.
    public mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

/// Column and direction defining the search window's table sort order.
public struct SearchWindowSort: Codable, Equatable, Hashable, Sendable {
    /// The column to sort by.
    public var column: SearchWindowColumn
    /// Whether to sort ascending or descending.
    public var direction: SortDirection

    /// Default sort: daemon relevance, highest score first.
    public static let defaultSort = SearchWindowSort(column: .relevance, direction: .descending)

    /// Creates a sort specification.
    public init(column: SearchWindowColumn, direction: SortDirection) {
        self.column = column
        self.direction = direction
    }
}

/// One row displayed in the Everything-style search window table, pre-formatted for fast rendering and sorting.
public struct SearchWindowRow: Equatable, Identifiable, Sendable {
    /// Stable unique row identifier (`path`, or `path:line` for content/definition hits).
    public let id: String
    /// Underlying search result item (for actions, editors, and `Launchable` checks).
    public let item: ResultItem
    /// Raw absolute path on disk (used by actions; never sanitized).
    public let path: String
    /// Display-safe file or folder name (control/bidi scalars replaced with `U+FFFD`).
    public let name: String
    /// Raw file name used for sorting.
    public let rawName: String
    /// Display-safe tilde-abbreviated parent folder path.
    public let folder: String
    /// Raw parent folder path used for sorting.
    public let rawFolder: String
    /// Size in bytes (`nil` for folders and content-match rows where the daemon sends no size).
    public let size: UInt64?
    /// Human-readable file size (`"–"` when `size` is `nil`).
    public let sizeFormatted: String
    /// Raw daemon kind string (`"file"`, `"dir"`, `"link"`, or `"match"`).
    public let kindCode: String
    /// Localized display label for the Kind column (derived without disk I/O).
    public let kindLabel: String
    /// Modification timestamp in seconds since the Unix epoch (`nil` for content-match rows).
    public let mtime: Int64?
    /// Modification date derived from `mtime`.
    public let modifiedAt: Date?
    /// Match relevance score from the daemon.
    public let score: Int32
    /// True when the entry is a directory (`kind == "dir"`).
    public let isDirectory: Bool
    /// 1-based line number for content/definition hits (`nil` for file-name hits).
    public let lineNumber: Int?
    /// Display-safe trimmed matching line text (`nil` for file-name hits).
    public let matchText: String?

    /// Builds a table row from a ``ResultItem`` without touching disk.
    public init(item: ResultItem) {
        self.id = item.id
        self.item = item
        self.path = item.path
        let nsPath = item.path as NSString
        let last = nsPath.lastPathComponent
        let parent = nsPath.deletingLastPathComponent
        self.rawName = last
        self.name = DisplaySafe.name(last)
        self.rawFolder = parent
        self.folder = DisplaySafe.name((parent as NSString).abbreviatingWithTildeInPath)

        switch item {
        case let .file(hit):
            let dir = hit.kind == "dir"
            self.isDirectory = dir
            self.kindCode = hit.kind
            self.size = dir ? nil : hit.size
            self.sizeFormatted = dir ? "–" : ByteCountFormatter.string(fromByteCount: Int64(clamping: hit.size), countStyle: .file)
            self.mtime = hit.mtime
            self.modifiedAt = hit.mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(hit.mtime)) : nil
            self.score = hit.score
            self.kindLabel = Self.describeKind(kindCode: hit.kind, fileName: last)
            self.lineNumber = nil
            self.matchText = nil
        case let .line(_, match):
            self.isDirectory = false
            self.kindCode = "match"
            self.size = nil
            self.sizeFormatted = "–"
            self.mtime = nil
            self.modifiedAt = nil
            self.score = 0
            self.kindLabel = Self.describeKind(kindCode: "file", fileName: last)
            self.lineNumber = match.line
            self.matchText = DisplaySafe.name(match.text.trimmingCharacters(in: .whitespaces))
        }
    }

    /// Derives a concise localized Kind label from the daemon kind and extension without touching disk.
    public static func describeKind(kindCode: String, fileName: String) -> String {
        switch kindCode {
        case "dir":
            if (fileName as NSString).pathExtension.lowercased() == "app" {
                return String(localized: "Application", bundle: .module)
            }
            return String(localized: "Folder", bundle: .module)
        case "link":
            return String(localized: "Alias", bundle: .module)
        default:
            let ext = (fileName as NSString).pathExtension
            guard !ext.isEmpty else { return String(localized: "File", bundle: .module) }
            return ext.uppercased()
        }
    }

    /// Sorts `rows` deterministically by `sort`, breaking ties by path and line number.
    public static func sort(_ rows: [SearchWindowRow], by sort: SearchWindowSort) -> [SearchWindowRow] {
        let asc = sort.direction == .ascending
        return rows.sorted { lhs, rhs in
            let order: ComparisonResult
            switch sort.column {
            case .relevance:
                order = compareValues(lhs.score, rhs.score)
            case .name:
                order = lhs.rawName.localizedStandardCompare(rhs.rawName)
            case .folder:
                order = lhs.rawFolder.localizedStandardCompare(rhs.rawFolder)
            case .size:
                order = compareOptional(lhs.size, rhs.size)
            case .kind:
                order = lhs.kindLabel.localizedStandardCompare(rhs.kindLabel)
            case .modified:
                order = compareOptional(lhs.mtime, rhs.mtime)
            }
            if order != .orderedSame {
                return asc ? order == .orderedAscending : order == .orderedDescending
            }
            if lhs.path != rhs.path { return lhs.path < rhs.path }
            return (lhs.lineNumber ?? 0) < (rhs.lineNumber ?? 0)
        }
    }

    private static func compareValues<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
        return .orderedSame
    }

    private static func compareOptional<T: Comparable>(_ a: T?, _ b: T?) -> ComparisonResult {
        switch (a, b) {
        case let (x?, y?): compareValues(x, y)
        case (nil, nil): .orderedSame
        case (nil, _?): .orderedAscending
        case (_?, nil): .orderedDescending
        }
    }
}

/// Pure status-bar copy formatting for the Everything-style search window.
public enum SearchWindowStatus {
    /// Formats the total result count (noting when the 1,000-result cap was reached).
    ///
    /// - Parameters:
    ///   - count: Number of rows currently shown.
    ///   - hitCap: True when the daemon returned at least the query's result cap.
    public static func resultSummary(count: Int, hitCap: Bool) -> String {
        if hitCap {
            return String(localized: "\(count) results (limit reached)", bundle: .module)
        }
        if count == 1 {
            return String(localized: "1 result", bundle: .module)
        }
        return String(localized: "\(count) results", bundle: .module)
    }

    /// Formats the current selection count and combined size (nil when nothing is selected).
    public static func selectionSummary(selected: [SearchWindowRow]) -> String? {
        guard !selected.isEmpty else { return nil }
        let knownSizes = selected.compactMap(\.size)
        if !knownSizes.isEmpty {
            let total = knownSizes.reduce(UInt64(0)) { $0 &+ $1 }
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(clamping: total), countStyle: .file)
            return String(localized: "\(selected.count) selected (\(formatted))", bundle: .module)
        }
        return String(localized: "\(selected.count) selected", bundle: .module)
    }
}
