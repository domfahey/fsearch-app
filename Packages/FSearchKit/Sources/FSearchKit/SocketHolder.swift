import Darwin
import Foundation
import Security

/// Who holds the daemon's socket, read from `<dataDir>/socket.lock`. The
/// daemon writes its pid there (decimal text, no newline) after taking the
/// lock. Only read, never locked: taking the lock, even briefly, could make a
/// daemon starting at that moment give up.
public enum SocketHolder: Equatable, Sendable {
    /// No lock file, no pid, or the pid isn't running: nobody we can name.
    case none
    /// Our bundled helper: our bundle's helper, or a moved helper signed by our team.
    case ours
    /// Some other process, e.g. a CLI install's daemon.
    case other

    /// The pid in a socket.lock; pids 0 and 1 are never a daemon.
    public static func pid(fromLock text: String) -> Int32? {
        guard let p = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), p > 1 else { return nil }
        return p
    }

    /// The code-signing identifier release.sh gives the bundled helper.
    public static let helperIdentifier = "com.domfahey.fsearch.daemon"

    /// A Developer ID (or other Apple-issued) certificate of our team. The app
    /// satisfies it only in a release build.
    public static let teamRequirement = #"anchor apple generic and certificate leaf[subject.OU] = "MR3WJZ83MR""#

    /// What a moved helper's signature must satisfy to count as ours: our
    /// identifier on our team's certificate. An identifier alone isn't enough,
    /// since an ad-hoc signature can claim any identifier.
    public static let helperRequirement = #"identifier "\#(helperIdentifier)" and "# + teamRequirement

    /// Where a helper sits inside its app.
    static let helperPlace = "/Contents/Helpers/fsearch"

    /// Where an unsigned copy of our helper sits inside its app. After an update
    /// (Sparkle, or Finder replacing the app) the old helper keeps running
    /// from wherever its bundle went: the Trash or a temp folder.
    static let helperSuffix = "/FSearch.app" + helperPlace

    /// Whether the running app is signed by our team, checked once.
    public static let appIsTeamSigned = isAppTeamSigned()

    /// Classifies a live holder.
    ///
    /// It is ``ours`` only if it is:
    /// - our bundle's helper, `<bundlePath>/Contents/Helpers/fsearch`, and nothing else in the bundle;
    /// - a helper outside the bundle (or one whose file is gone) that satisfies ``helperRequirement``;
    /// - from an app not signed by our team (a dev or ad-hoc build), an FSearch.app's helper.
    ///
    /// Anything else is ``other``, never taken over.
    ///
    /// - Parameters:
    ///   - pid: The pid in socket.lock.
    ///   - path: The pid's executable, nil when it isn't running (or its file is gone).
    ///   - signedAsHelper: Whether the pid's signature satisfies ``helperRequirement``.
    ///   - appTeamSigned: Whether the app itself satisfies ``teamRequirement``.
    ///   - bundlePath: The app's bundle.
    public static func classify(
        pid: Int32?, path: String?, signedAsHelper: Bool = false, appTeamSigned: Bool = true, bundlePath: String
    ) -> SocketHolder {
        guard pid != nil else { return .none }
        guard let path else { return signedAsHelper ? .ours : .none }
        let bundle = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        if path.hasPrefix(bundle + "/") { return path == bundle + helperPlace ? .ours : .other }
        if signedAsHelper && path.hasSuffix(helperPlace) { return .ours }
        if !appTeamSigned && path.hasSuffix(helperSuffix) { return .ours }
        return .other
    }

    /// The running process's executable, or nil if there is no such process.
    public static func executablePath(pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Whether the running process's code signature is valid and satisfies
    /// `requirement`. False if there is no such process, it isn't signed, or
    /// the requirement doesn't parse.
    ///
    /// - Parameters:
    ///   - pid: The process to check.
    ///   - requirement: A code-signing requirement in text form (tests pass their own).
    public static func isSignedAsHelper(pid: Int32, requirement: String = helperRequirement) -> Bool {
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else { return false }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }

    /// Whether the running app's code signature is valid and satisfies
    /// `requirement`. False if it isn't signed or the requirement doesn't parse.
    ///
    /// - Parameter requirement: A code-signing requirement in text form (tests pass their own).
    public static func isAppTeamSigned(requirement: String = teamRequirement) -> Bool {
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }

    /// The live holder of the socket in `dataDir`, judged against `bundlePath`
    /// (the app's bundle). A few cheap syscalls, fine on the main thread.
    ///
    /// - Parameters:
    ///   - dataDir: The folder holding socket.lock.
    ///   - bundlePath: The app's bundle.
    ///   - path: A pid's executable (tests inject one).
    ///   - signedAsHelper: Whether a pid is signed as our helper (tests inject one).
    ///   - appTeamSigned: Whether the app is signed by our team (tests inject one).
    public static func read(
        dataDir: URL, bundlePath: String,
        path: (Int32) -> String? = executablePath(pid:),
        signedAsHelper: (Int32) -> Bool = { isSignedAsHelper(pid: $0) },
        appTeamSigned: () -> Bool = { appIsTeamSigned }
    ) -> SocketHolder {
        let text = try? String(contentsOf: dataDir.appendingPathComponent("socket.lock"), encoding: .utf8)
        guard let pid = text.flatMap(pid(fromLock:)) else { return .none }
        return classify(
            pid: pid, path: path(pid), signedAsHelper: signedAsHelper(pid), appTeamSigned: appTeamSigned(), bundlePath: bundlePath)
    }
}
