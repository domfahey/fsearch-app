import Testing

@testable import FSearchKit

@Suite struct MessagesTests {
    @Test func messages() {
        #expect(UserMessage.forPhase(.results) == nil)
        #expect(UserMessage.forPhase(.loading) == nil)
        #expect(UserMessage.forPhase(.indexing) == "Indexing your disk… results will appear shortly")
        #expect(UserMessage.forPhase(.failed(.disconnected)) == "Starting search…")
        #expect(UserMessage.forPhase(.failed(.timeout)) == "Starting search…")
        #expect(UserMessage.forPhase(.failed(.indexing("indexing (~20s)"))) == "Indexing your disk… results will appear shortly")
        #expect(UserMessage.forPhase(.failed(.daemon("regex parse error: unclosed group"))) == "regex parse error: unclosed group")
        #expect(UserMessage.forPhase(.failed(.badReply("x"))) == "Unexpected reply from the search daemon: x")
    }
}
