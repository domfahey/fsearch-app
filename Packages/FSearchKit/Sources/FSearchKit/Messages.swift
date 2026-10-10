/// What the panel says instead of results, if anything.
public enum UserMessage {
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
