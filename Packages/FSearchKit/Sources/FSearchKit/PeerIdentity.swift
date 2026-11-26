import Darwin
import Foundation
import Security

/// Names the process on the other end of a connected daemon socket by its code signature.
///
/// The kernel's audit token for the socket's peer (`LOCAL_PEERTOKEN`) identifies the very
/// process that accepted the connection, including its pid version, so it can't be faked by
/// writing a pid into socket.lock or raced by pid reuse. The decision itself is
/// ``SocketHolder/classifyPeer(path:signedAsHelper:appTeamSigned:bundlePath:)``; the closures
/// are the thin Security-framework adapter, replaced in tests.
public struct PeerIdentifier: Sendable {
    /// The peer's audit token, nil when the kernel won't give one.
    var auditToken: @Sendable (Int32) -> Data?
    /// The executable of the code an audit token names, nil if it names none.
    var path: @Sendable (Data) -> String?
    /// Whether the code an audit token names has a valid signature satisfying a requirement.
    var satisfies: @Sendable (Data, String) -> Bool
    /// Whether the app itself is signed by our team (dev builds relax the helper's team check).
    var appTeamSigned: @Sendable () -> Bool
    /// The app's bundle, whose own helper is ours by its path.
    var bundlePath: String

    /// The live identifier: audit token, code-signing lookups and the app's own signature.
    ///
    /// - Parameter bundlePath: The app's bundle.
    public static func live(bundlePath: String) -> PeerIdentifier {
        PeerIdentifier(
            auditToken: { auditToken(socket: $0) }, path: { path(auditToken: $0) },
            satisfies: { satisfies(auditToken: $0, requirement: $1) }, appTeamSigned: { SocketHolder.appIsTeamSigned },
            bundlePath: bundlePath)
    }

    /// Who is on the other end of `fd`: ``SocketHolder/ours`` or ``SocketHolder/other``, or nil
    /// when the peer's audit token can't be read (the caller then falls back to socket.lock).
    ///
    /// - Parameter fd: A connected Unix socket.
    public func identify(socket fd: Int32) -> SocketHolder? {
        guard let token = auditToken(fd) else { return nil }
        return SocketHolder.classifyPeer(
            path: path(token), signedAsHelper: { satisfies(token, SocketHolder.helperRequirement) },
            appTeamSigned: appTeamSigned, bundlePath: bundlePath)
    }

    /// The audit token of a connected Unix socket's peer, as raw bytes.
    static func auditToken(socket fd: Int32) -> Data? {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0, len == MemoryLayout<audit_token_t>.size else {
            return nil
        }
        return withUnsafeBytes(of: &token) { Data($0) }
    }

    /// The running code an audit token names; nil if it isn't a token or names no live process.
    private static func code(auditToken: Data) -> SecCode? {
        guard auditToken.count == MemoryLayout<audit_token_t>.size else { return nil }
        var code: SecCode?
        let attrs = [kSecGuestAttributeAudit: auditToken] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess else { return nil }
        return code
    }

    /// The on-disk executable of the code an audit token names.
    static func path(auditToken: Data) -> String? {
        guard let code = code(auditToken: auditToken) else { return nil }
        var staticCode: SecStaticCode?
        var url: CFURL?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopyPath(staticCode, [], &url) == errSecSuccess, let url
        else { return nil }
        return (url as URL).path
    }

    /// Whether the code an audit token names is validly signed and satisfies `requirement`.
    static func satisfies(auditToken: Data, requirement: String) -> Bool {
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req,
            let code = code(auditToken: auditToken)
        else { return false }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }
}
