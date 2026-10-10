import Testing
@testable import FSearchKit

@Suite struct DaemonPlanTests {
    @Test func useWhatIsRunning() {
        #expect(DaemonPlan.decide(existingAnswers: true) == .useExisting)
        #expect(DaemonPlan.decide(existingAnswers: false) == .registerBundled)
    }
}
