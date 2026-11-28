import Foundation

/// A parsed `fsearch://` URL that opens FSearch with a pre-filled query, search mode, and optional UI override.
///
/// Only `fsearch://search` (with optional `q`, `mode`, and `ui` query items) is accepted; unknown schemes,
/// hosts, paths, authority components, modes, and UI values are rejected. A URL never runs file actions directly —
/// it only pre-fills the search box and refreshes results.
public struct SearchURL: Equatable, Sendable {
    /// The registered URL scheme (`fsearch`).
    public static let scheme = "fsearch"
    /// The only supported URL action host (`search`).
    public static let host = "search"
    /// Maximum query length in Unicode scalars accepted from a URL.
    public static let maxQueryLength = 1000

    /// The sanitized search query to place in the search field.
    public let query: String
    /// The search mode to activate.
    public let mode: SearchMode
    /// Optional explicit UI override (`panel` or `window`); `nil` uses the user's Settings preference.
    public let interface: SearchInterface?

    /// Creates a search URL payload, sanitizing control characters, line breaks, and excessive length.
    ///
    /// - Parameters:
    ///   - query: The search text (default empty).
    ///   - mode: The search mode (default ``SearchMode/names``).
    ///   - interface: Optional explicit UI override (`nil` follows Settings).
    public init(query: String = "", mode: SearchMode = .names, interface: SearchInterface? = nil) {
        self.query = Self.sanitize(query)
        self.mode = mode
        self.interface = interface
    }

    /// Parses a `fsearch://search` URL.
    ///
    /// Accepted forms:
    /// - `fsearch://search` (opens empty in file-name mode)
    /// - `fsearch://search?q=<percent-encoded query>`
    /// - `fsearch://search?q=<query>&mode=names|content|symbols`
    /// - `fsearch://search?q=<query>&ui=panel|window`
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
        var interface: SearchInterface?
        for item in components.queryItems ?? [] {
            switch item.name.lowercased() {
            case "q":
                query = item.value ?? ""
            case "mode":
                guard let parsed = parseMode(item.value) else { return nil }
                mode = parsed
            case "ui":
                guard let parsed = SearchInterface.parseOverride(item.value) else { return nil }
                interface = parsed
            default:
                break
            }
        }
        return SearchURL(query: query, mode: mode, interface: interface)
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
        if let interface {
            items.append(URLQueryItem(name: "ui", value: interface.rawValue))
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
