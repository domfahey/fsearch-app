import Darwin
import Foundation

/// The real fsearch daemon, isolated: temp HOME and FSEARCH_ROOT. Never the
/// user's index.
final class RealDaemon {
    let home: URL
    let root: URL
    let process = Process()
    /// Write end of the watchdog pipe; only this process holds it (the child
    /// gets the read end as stdin). Closing it, or dying, makes the wrapper
    /// stop the daemon and remove `home`.
    private let watchdog = Pipe()
    var socketPath: String { home.path + "/Library/Application Support/FSearch/fsearch.sock" }

    static var binary: URL? {
        let p = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Vendor/fsearch").standardized
        return FileManager.default.isExecutableFile(atPath: p.path) ? p : nil
    }

    /// `sh -c` wrapper: $0 = binary, $1 = temp home. Starts the daemon with
    /// stdin detached, blocks reading its own stdin (the watchdog pipe) until
    /// EOF, then SIGTERM, SIGKILL after 5 s, and removes the temp dir.
    static let wrapperScript = """
        exec 2>/dev/null
        "$0" serve </dev/null >/dev/null 2>&1 &
        d=$!
        read -r _ || :
        kill "$d" 2>/dev/null
        i=0
        while kill -0 "$d" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
        kill -9 "$d" 2>/dev/null
        wait "$d" 2>/dev/null
        rm -rf "$1"
        """

    /// Kill orphaned fixture daemons from earlier, hard-killed test runs: this
    /// repo's Vendor/fsearch, parent gone (ppid 1), HOME under /private/tmp/fsk-.
    /// Anything else (the user's own daemon, live fixtures) is left alone.
    static let sweepOnce: Void = sweep()

    static func sweep() {
        guard let bin = binary?.path else { return }
        for line in sh("/bin/ps", ["-axww", "-o", "pid=,ppid=,command="]).split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard f.count == 3, f[1] == "1", f[2] == "\(bin) serve", let pid = Int32(f[0]) else { continue }
            let env = sh("/bin/ps", ["eww", "-o", "pid=,command=", "-p", String(pid)])
            guard let r = env.range(of: "HOME=/private/tmp/fsk-") else { continue }
            let home = String(env[r.lowerBound...].dropFirst(5).prefix { $0 != " " && $0 != "\n" })
            kill(pid, SIGTERM)
            for _ in 0..<50 where kill(pid, 0) == 0 { Thread.sleep(forTimeInterval: 0.1) }
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            try? FileManager.default.removeItem(atPath: home)
        }
    }

    static func sh(_ exe: String, _ args: [String]) -> String {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    init(files: [String: String]) throws {
        RealDaemon.sweepOnce
        home = URL(fileURLWithPath: "/private/tmp/fsk-\(UUID().uuidString.prefix(6))")
        root = home.appendingPathComponent("root")
        do {
            for (rel, body) in files {
                let f = root.appendingPathComponent(rel)
                try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
                try body.write(to: f, atomically: true, encoding: .utf8)
            }
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", RealDaemon.wrapperScript, RealDaemon.binary!.path, home.path]
            process.standardInput = watchdog
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

    /// Close the watchdog pipe; the wrapper stops the daemon (<= ~5 s) and
    /// removes the temp dir. Bounded: SIGKILL the wrapper after 8 s.
    private func stop() {
        try? watchdog.fileHandleForWriting.close()
        guard process.isRunning else { return }
        for _ in 0..<80 where process.isRunning {
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
