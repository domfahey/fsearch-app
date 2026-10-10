import Testing
@testable import FSearchKit

@Suite struct DaemonPlanTests {
    @Test func useWhatIsRunning() {
        #expect(DaemonPlan.decide(existingAnswers: true) == .useExisting)
        #expect(DaemonPlan.decide(existingAnswers: false) == .registerBundled)
    }

    @Test func restartOnlyWhatWeOwn() {
        #expect(DaemonPlan.restartAction(owns: true) == .reregister)
        #expect(DaemonPlan.restartAction(owns: false) == .refreshOnly)
    }
}
