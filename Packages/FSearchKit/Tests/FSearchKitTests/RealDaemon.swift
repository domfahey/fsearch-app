import Foundation

/// The real fsearch daemon, isolated: temp HOME and FSEARCH_ROOT. Never the
/// user's index.
final class RealDaemon {
    let home: URL
    let root: URL
    let process = Process()
    var socketPath: String { home.path + "/Library/Application Support/FSearch/fsearch.sock" }

    static var binary: URL? {
        let p = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Vendor/fsearch").standardized
        return FileManager.default.isExecutableFile(atPath: p.path) ? p : nil
    }

    init(files: [String: String]) throws {
        home = URL(fileURLWithPath: "/private/tmp/fsk-\(UUID().uuidString.prefix(6))")
        root = home.appendingPathComponent("root")
        for (rel, body) in files {
            let f = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: f, atomically: true, encoding: .utf8)
        }
        process.executableURL = RealDaemon.binary!
        process.arguments = ["serve"]
        process.environment = ["HOME": home.path, "FSEARCH_ROOT": root.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    deinit {
        process.terminate()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: home)
    }
}
