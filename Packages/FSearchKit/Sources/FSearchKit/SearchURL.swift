import Foundation

/// A parsed `fsearch://` URL that opens the launcher panel with a pre-filled query and search mode.
///
/// Only `fsearch://search` (with optional `q` and `mode` query items) is accepted; unknown schemes,
/// hosts, paths, authority components, and modes are rejected. A URL never runs file actions directly —
/// it only pre-fills the search box and refreshes results.
public struct SearchURL: Equatable, Sendable {
    /// The registered URL scheme (`fsearch`).
    public static let scheme = "fsearch"
    /// The only supported URL action host (`search`).
    public static let host = "search"
    /// Maximum query length in Unicode scalars accepted from a URL.
    public static let maxQueryLength = 1000

    /// The sanitized search query to place in the panel's search field.
    public let query: String
    /// The search mode to activate in the panel.
    public let mode: SearchMode

    /// Creates a search URL payload, sanitizing control characters, line breaks, and excessive length.
    ///
    /// - Parameters:
    ///   - query: The search text (default empty).
    ///   - mode: The search mode (default ``SearchMode/names``).
    public init(query: String = "", mode: SearchMode = .names) {
        self.query = Self.sanitize(query)
        self.mode = mode
    }

    /// Parses a `fsearch://search` URL.
    ///
    /// Accepted forms:
    /// - `fsearch://search` (opens the panel empty in file-name mode)
    /// - `fsearch://search?q=<percent-encoded query>`
    /// - `fsearch://search?q=<query>&mode=names|content|symbols`
    ///
    /// - Parameter url: The incoming URL from LaunchServices or another app.
    /// - Returns: A sanitized ``SearchURL``, or `nil` if the URL is not a valid FSearch search link.
    public static func parse(_ url: URL) -> SearchURL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard components.scheme?.lowercased() == scheme else { return nil }
        guard components.user == nil, components.password == nil, components.port == nil else { return nil }
        guard components.host?.lowercased() == host else { return nil }
        guard components.path.isEmpty || components.path == "/" else { return nil }

        var query = ""
        var mode: SearchMode = .names
        for item in components.queryItems ?? [] {
            switch item.name.lowercased() {
            case "q":
                query = item.value ?? ""
            case "mode":
                guard let parsed = parseMode(item.value) else { return nil }
                mode = parsed
            default:
                break
            }
        }
        return SearchURL(query: query, mode: mode)
    }

    /// Encodes this search as a `fsearch://search` URL that round-trips through ``parse(_:)``.
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        var items: [URLQueryItem] = []
        if !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if let modeName = Self.modeName(mode) {
            items.append(URLQueryItem(name: "mode", value: modeName))
        }
        components.queryItems = items.isEmpty ? nil : items
        guard let built = components.url else {
            preconditionFailure("SearchURL failed to build URLComponents")
        }
        return built
    }

    private static func parseMode(_ raw: String?) -> SearchMode? {
        switch raw?.lowercased() {
        case "names": .names
        case "content": .content
        case "symbols": .symbols
        default: nil
        }
    }

    private static func modeName(_ mode: SearchMode) -> String? {
        switch mode {
        case .names: nil
        case .content: "content"
        case .symbols: "symbols"
        }
    }

    /// Replaces line/tab separators with spaces, drops control characters, and caps length at grapheme boundaries.
    static func sanitize(_ raw: String) -> String {
        let bufferLimit = maxQueryLength + 32
        var normalized = ""
        normalized.reserveCapacity(min(raw.utf8.count, maxQueryLength))
        var keptScalars = 0
        var previousWasCR = false
        for scalar in raw.unicodeScalars {
            if scalar == "\r" {
                normalized.append(" ")
                keptScalars += 1
                previousWasCR = true
            } else if scalar == "\n" {
                if !previousWasCR {
                    normalized.append(" ")
                    keptScalars += 1
                }
                previousWasCR = false
            } else {
                previousWasCR = false
                if scalar == "\t" || scalar == "\u{2028}" || scalar == "\u{2029}" {
                    normalized.append(" ")
                    keptScalars += 1
                } else if scalar.properties.generalCategory == .control {
                    continue
                } else {
                    normalized.unicodeScalars.append(scalar)
                    keptScalars += 1
                }
            }
            if keptScalars >= bufferLimit { break }
        }
        guard keptScalars > maxQueryLength else { return normalized }
        var capped = ""
        var count = 0
        for character in normalized {
            let n = character.unicodeScalars.count
            guard count + n <= maxQueryLength else { break }
            capped.append(character)
            count += n
        }
        return capped
    }
}
