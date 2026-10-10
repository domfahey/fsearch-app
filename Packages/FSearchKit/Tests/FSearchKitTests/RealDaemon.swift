import Darwin
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
        do {
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
        } catch {
            // deinit does not run when init throws, so clean up here.
            try? FileManager.default.removeItem(at: home)
            throw error
        }
    }

    /// Terminate, wait up to 5 s, then SIGKILL. Only a launched process is stopped.
    private func stop() {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<50 where process.isRunning {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    deinit {
        stop()
        try? FileManager.default.removeItem(at: home)
    }
}
