import Testing
@testable import FSearchKit

@Suite struct RestartBudgetTests {
    @Test func allowsThreeRestartsPerOutage() {
        var b = RestartBudget()
        let spent = (0..<5).map { _ in b.spend() }
        #expect(spent == [true, true, true, false, false])
    }

    @Test func resultsRefillTheBudget() {
        var b = RestartBudget(max: 2)
        let before = (0..<3).map { _ in b.spend() }
        #expect(before == [true, true, false])
        b.reset()
        let after = b.spend()
        #expect(after)
    }
}
