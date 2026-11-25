import Foundation

/// What the panel says instead of results, if anything.
public enum UserMessage {
    /// A daemon that times out, or is still gone after the restarts ran out.
    static let notAnswering = String(localized: "The search helper isn't answering", bundle: .module)

    /// The text for a search phase, or nil when results (or nothing) should show.
    ///
    /// A dropped daemon reads as "Starting search…" since it is usually just starting;
    /// a timeout, or a disconnect once the restarts ran out (`helperGaveUp`), reads as
    /// ``notAnswering``.
    public static func forPhase(_ p: SearchPhase, helperGaveUp: Bool = false) -> String? {
        switch p {
        case .idle, .loading, .results: nil
        case .indexing: String(localized: "Indexing your disk… results will appear shortly", bundle: .module)
        case .failed(.timeout): notAnswering
        case .failed(.disconnected): helperGaveUp ? notAnswering : String(localized: "Starting search…", bundle: .module)
        case .failed(.indexing(_)): String(localized: "Indexing your disk… results will appear shortly", bundle: .module)
        case let .failed(e): e.description  // .daemon and .badReply
        }
    }
}
