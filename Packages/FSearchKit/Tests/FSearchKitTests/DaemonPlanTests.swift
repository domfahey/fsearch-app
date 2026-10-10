import Foundation
import Testing

@testable import FSearchKit

@Suite struct DaemonPlanTests {
    @Test func aDaemonThatAnswersIsUsedWhateverElseIsTrue() {
        for own in DaemonPlan.ServiceStatus.allCases {
            for cli in [false, true] {
                #expect(DaemonPlan.decide(existingAnswers: true, ownStatus: own, cliAgentInstalled: cli) == .useExisting)
            }
        }
    }

    @Test func anEnabledHelperIsNeverRegisteredAgain() {
        #expect(DaemonPlan.decide(existingAnswers: false, ownStatus: .enabled, cliAgentInstalled: false) == .refreshOwn)
        #expect(DaemonPlan.decide(existingAnswers: false, ownStatus: .enabled, cliAgentInstalled: true) == .refreshOwn)
    }

    @Test func aBrieflyDownCLIDaemonIsWaitedForNotTakenOver() {
        // A CLI agent's plist alone isn't a daemon: wait longer for it, then start ours.
        for own in [DaemonPlan.ServiceStatus.notRegistered, .notFound, .requiresApproval] {
            #expect(DaemonPlan.decide(existingAnswers: false, ownStatus: own, cliAgentInstalled: true) == .recheckThenRegister)
        }
        #expect(DaemonPlan.recheckWindow(cliAgentInstalled: true) == .seconds(10))
        #expect(DaemonPlan.recheckWindow(cliAgentInstalled: false) == DaemonPlan.recheckWindow)
    }

    @Test func aLeftoverCLIPlistFallsBackToOurHelper() {
        #expect(DaemonPlan.afterRecheck(existingAnswers: false, ownStatus: .notRegistered) == .registerBundled)
        #expect(DaemonPlan.afterRecheck(existingAnswers: false, ownStatus: .notFound) == .registerBundled)
        #expect(DaemonPlan.afterRecheck(existingAnswers: false, ownStatus: .requiresApproval) == .needsApproval)
        #expect(DaemonPlan.afterRecheck(existingAnswers: true, ownStatus: .requiresApproval) == .useExisting)
    }

    @Test func aPendingApprovalIsShownNotRegisteredAgain() {
        #expect(DaemonPlan.decide(existingAnswers: false, ownStatus: .requiresApproval, cliAgentInstalled: false) == .needsApproval)
    }

    @Test func nothingAroundMeansRecheckBeforeRegistering() {
        for own in [DaemonPlan.ServiceStatus.notRegistered, .notFound] {
            #expect(DaemonPlan.decide(existingAnswers: false, ownStatus: own, cliAgentInstalled: false) == .recheckThenRegister)
        }
        #expect(DaemonPlan.afterRecheck(existingAnswers: true, ownStatus: .notRegistered) == .useExisting)
        #expect(DaemonPlan.afterRecheck(existingAnswers: false, ownStatus: .notRegistered) == .registerBundled)
        #expect(DaemonPlan.recheckWindow <= .seconds(5) && DaemonPlan.recheckWindow >= .seconds(2))
    }

    @Test func registeringThatNeedsApprovalSaysSo() {
        #expect(DaemonPlan.afterRegister(ownStatus: .requiresApproval) == .needsApproval)
        #expect(DaemonPlan.afterRegister(ownStatus: .enabled) == .refreshOwn)
        #expect(DaemonPlan.afterRegister(ownStatus: .notRegistered) == .refreshOwn)
    }

    @Test func restartOnlyWhatWeOwn() {
        #expect(DaemonPlan.restartAction(owns: true, answers: true) == .reregister)
        #expect(DaemonPlan.restartAction(owns: true, answers: false) == .reregister)
        // Someone else's daemon that answers is left running.
        #expect(DaemonPlan.restartAction(owns: false, answers: true) == .refreshOnly)
        // Nothing answers and nothing is ours: start one (start() rechecks first).
        #expect(DaemonPlan.restartAction(owns: false, answers: false) == .start)
    }

    @Test func noAnswerKeepsAPendingApprovalUntilTheHelperIsEnabled() {
        // Test mode (no service status): plain failure.
        #expect(DaemonPlan.noAnswer(wasNeedingApproval: true, ownStatus: nil) == .failed)
        #expect(DaemonPlan.noAnswer(wasNeedingApproval: false, ownStatus: nil) == .failed)
        #expect(DaemonPlan.noAnswer(wasNeedingApproval: true, ownStatus: .requiresApproval) == .needsApproval)
        #expect(DaemonPlan.noAnswer(wasNeedingApproval: true, ownStatus: .notRegistered) == .needsApproval)
        #expect(DaemonPlan.noAnswer(wasNeedingApproval: true, ownStatus: .enabled) == .failed)
        #expect(DaemonPlan.noAnswer(wasNeedingApproval: false, ownStatus: .requiresApproval) == .needsApproval)
        #expect(DaemonPlan.noAnswer(wasNeedingApproval: false, ownStatus: .enabled) == .failed)
        #expect(DaemonPlan.noAnswer(wasNeedingApproval: false, ownStatus: .notRegistered) == .failed)
    }
}

@Suite struct RecoveryCheckTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    private func ask(_ r: inout RecoveryCheck, _ unhealthy: Bool, _ now: Date) -> Bool {
        r.shouldRefresh(daemonUnhealthy: unhealthy, now: now)
    }

    @Test func onlyAnUnhealthyStateIsRechecked() {
        var r = RecoveryCheck()
        #expect(!ask(&r, false, t0))
        #expect(ask(&r, true, t0))
    }

    @Test func atMostOncePerInterval() {
        var r = RecoveryCheck(interval: 5)
        #expect(ask(&r, true, t0))
        #expect(!ask(&r, true, t0.addingTimeInterval(1)))
        #expect(!ask(&r, true, t0.addingTimeInterval(4.9)))
        #expect(ask(&r, true, t0.addingTimeInterval(5)))
    }

    @Test func aHealthyCheckDoesNotSpendTheInterval() {
        var r = RecoveryCheck(interval: 5)
        #expect(!ask(&r, false, t0))
        #expect(ask(&r, true, t0.addingTimeInterval(1)))
    }
}
