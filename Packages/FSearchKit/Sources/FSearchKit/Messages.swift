/// What the panel says instead of results, if anything.
public enum UserMessage {
    /// The text for a search phase, or nil when results (or nothing) should show.
    ///
    /// A dropped or slow daemon reads as "Starting search…" since it is usually just starting.
    public static func forPhase(_ p: SearchPhase) -> String? {
        switch p {
        case .idle, .loading, .results: nil
        case .indexing: "Indexing your disk… results will appear shortly"
        case .failed(.disconnected), .failed(.timeout): "Starting search…"
        case .failed(.indexing(_)): "Indexing your disk… results will appear shortly"
        case let .failed(e): e.description  // .daemon and .badReply
        }
    }
}
