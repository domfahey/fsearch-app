import Foundation
import Testing

@testable import FSearchKit

@Suite struct IssueReportTests {
    let facts = IssueReport(
        appVersion: "0.3.1", build: "42", macOS: "Version 15.1 (Build 24B83)", chip: .appleSilicon,
        daemonInstall: .cli, daemonState: .needsApproval)

    func items(_ url: URL) -> [String: String] {
        let c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        return Dictionary(uniqueKeysWithValues: c.queryItems!.map { ($0.name, $0.value ?? "") })
    }

    @Test func targetsTheBugFormWithItsFieldIds() {
        let url = IssueReport.url(for: facts)
        #expect(url.absoluteString.hasPrefix("https://github.com/domfahey/fsearch-app/issues/new?"))
        let q = items(url)
        #expect(q["template"] == "bug_report.yml")
        #expect(q["macos"] == "Version 15.1 (Build 24B83)")
        #expect(q["chip"] == "Apple silicon")
        #expect(q["app-version"] == "0.3.1 (42)")
        #expect(q["daemon"] == "CLI (fsearch install --login)")
        #expect(q["index-details"]?.contains("needsApproval") == true)
    }

    @Test func encodesReservedCharacters() {
        let odd = IssueReport(
            appVersion: "1&2=3+4 #x", build: "", macOS: "a b", chip: .intel, daemonInstall: .bundled, daemonState: .running)
        let url = IssueReport.url(for: odd)
        #expect(!url.absoluteString.dropFirst(IssueReport.newIssueBase.count + 1).contains(" "))
        #expect(items(url)["app-version"] == "1&2=3+4 #x")
        #expect(items(url)["chip"] == "Intel")
    }

    @Test func unknownChipIsLeftForTheUser() {
        var f = facts; f.chip = nil
        #expect(items(IssueReport.url(for: f))["chip"] == nil)
        #expect(IssueReport.chip(machine: "arm64") == .appleSilicon)
        #expect(IssueReport.chip(machine: "x86_64") == .intel)
        #expect(IssueReport.chip(machine: "ppc") == nil)
    }

    @Test func carriesNoPathsAndStaysShort() {
        let s = IssueReport.url(for: facts).absoluteString
        #expect(!s.contains("%2F" + "Users"))
        #expect(!s.contains("/Users"))
        #expect(s.utf8.count < 8 * 1024)
        let long = IssueReport(
            appVersion: String(repeating: "9", count: 200), build: "1", macOS: String(repeating: "m", count: 200), chip: .intel,
            daemonInstall: .unsure, daemonState: .failed)
        #expect(IssueReport.url(for: long).absoluteString.utf8.count < 8 * 1024)
    }
}
