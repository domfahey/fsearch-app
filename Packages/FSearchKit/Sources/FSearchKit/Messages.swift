/// What the panel says instead of results, if anything.
public enum UserMessage {
    /// A daemon that times out, or is still gone after the restarts ran out.
    public static let notAnswering = "The search helper isn't answering"

    /// The text for a search phase, or nil when results (or nothing) should show.
    ///
    /// A dropped daemon reads as "Starting search…" since it is usually just starting;
    /// a timeout, or a disconnect once the restarts ran out (`helperGaveUp`), reads as
    /// ``notAnswering``.
    public static func forPhase(_ p: SearchPhase, helperGaveUp: Bool = false) -> String? {
        switch p {
        case .idle, .loading, .results: nil
        case .indexing: "Indexing your disk… results will appear shortly"
        case .failed(.timeout): notAnswering
        case .failed(.disconnected): helperGaveUp ? notAnswering : "Starting search…"
        case .failed(.indexing(_)): "Indexing your disk… results will appear shortly"
        case let .failed(e): e.description  // .daemon and .badReply
        }
    }
}
