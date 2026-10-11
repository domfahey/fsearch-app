import Testing

@testable import FSearchKit

@Suite struct MessagesCoverageTests {
    @Test func quietPhasesSayNothing() {
        #expect(UserMessage.forPhase(.idle) == nil)
        #expect(UserMessage.forPhase(.loading) == nil)
    }

    @Test func indexingShowsTheSameTextWhateverTheDaemonSaid() {
        let text = "Indexing your disk… results will appear shortly"
        #expect(UserMessage.forPhase(.indexing) == text)
        #expect(UserMessage.forPhase(.failed(.indexing("indexing (~20s)"))) == text)
        #expect(UserMessage.forPhase(.failed(.indexing(""))) == text)
    }

    @Test func badReplyIsPrefixed() {
        #expect(
            UserMessage.forPhase(.failed(.badReply("reply has no \"hits\"")))
                == "Unexpected reply from the search daemon: reply has no \"hits\"")
        #expect(UserMessage.forPhase(.failed(.badReply(""))) == "Unexpected reply from the search daemon: ")
    }

    @Test func daemonMessagePassesThroughVerbatim() {
        #expect(UserMessage.forPhase(.failed(.daemon(""))) == "The search daemon reported an error")
        #expect(UserMessage.forPhase(.failed(.daemon("bad filter: 🏡"))) == "bad filter: 🏡")
    }
}
