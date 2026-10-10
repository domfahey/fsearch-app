import Testing

@testable import FSearchKit

@Suite struct MessagesTests {
    @Test func messages() {
        #expect(UserMessage.forPhase(.results) == nil)
        #expect(UserMessage.forPhase(.loading) == nil)
        #expect(UserMessage.forPhase(.indexing) == "Indexing your disk… results will appear shortly")
        #expect(UserMessage.forPhase(.failed(.disconnected)) == "Starting search…")
        #expect(UserMessage.forPhase(.failed(.timeout)) == "The search helper isn't answering")
        #expect(UserMessage.forPhase(.failed(.indexing("indexing (~20s)"))) == "Indexing your disk… results will appear shortly")
        #expect(UserMessage.forPhase(.failed(.daemon("regex parse error: unclosed group"))) == "regex parse error: unclosed group")
        #expect(UserMessage.forPhase(.failed(.badReply("x"))) == "Unexpected reply from the search daemon: x")
    }

    @Test func aDisconnectAfterTheRestartsRanOutIsNotStarting() {
        #expect(UserMessage.forPhase(.failed(.disconnected), helperGaveUp: true) == UserMessage.notAnswering)
        #expect(UserMessage.forPhase(.failed(.timeout), helperGaveUp: true) == UserMessage.notAnswering)
        #expect(UserMessage.forPhase(.failed(.disconnected), helperGaveUp: false) == "Starting search…")
        // Other phases don't change.
        #expect(UserMessage.forPhase(.results, helperGaveUp: true) == nil)
        #expect(UserMessage.forPhase(.failed(.daemon("bad")), helperGaveUp: true) == "bad")
    }
}
