import Darwin
import FSearchKit
import Foundation

/// The deterministic fixture tree the real daemon indexes.
enum FixtureTree {
    static let seed: UInt64 = 0xF5EA_2C4B_E7C4_0001
    static let nameFiles = 50_000
    static let textFiles = 2_000

    static let words = [
        "alpha", "bravo", "cedar", "delta", "ember", "falcon", "garnet", "harbor", "iris", "juniper",
        "kepler", "lumen", "maple", "nimbus", "onyx", "pebble", "quartz", "raven", "sierra", "tundra",
        "umber", "vortex", "willow", "xenon", "yarrow", "zephyr", "heron", "lattice", "quantum", "needle",
        "module", "report", "invoice", "sketch", "backup", "draft", "final", "notes", "config", "assets",
    ]
    static let exts = ["rs", "swift", "txt", "md", "json", "png", "jpg", "log", "c", "h", "py", "pdf", "csv", "zip"]

    /// Creates the tree under `root`; returns the files and dirs created and
    /// the stem of one generated name (file #12345), used as the long query.
    static func build(at root: URL) throws -> (files: Int, dirs: Int, sample: String) {
        var rng = SplitMix64(seed: seed)
        let fm = FileManager.default
        var dirs = 0
        func mkdir(_ u: URL) throws { try fm.createDirectory(at: u, withIntermediateDirectories: true); dirs += 1 }
        func touch(_ path: String, _ body: String?) throws {
            let fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
            guard fd >= 0 else { throw BenchError("create \(path): errno \(errno)") }
            if let body {
                let n = body.utf8CString.count - 1
                _ = body.withCString { write(fd, $0, n) }
            }
            close(fd)
        }

        // Name corpus: 10 × 10 × 10 leaf folders, 50 empty files each.
        let leaves: [URL] = (0..<10).flatMap { a in
            (0..<10).flatMap { b in
                (0..<10).map { c in
                    root.appendingPathComponent(
                        "\(words[a])-\(a)/\(words[(a + b + 10) % words.count])-\(b)/\(words[(a * 3 + b + c) % words.count])-\(c)")
                }
            }
        }
        for l in leaves { try mkdir(l) }
        let perLeaf = nameFiles / leaves.count
        var sample = ""
        for (li, leaf) in leaves.enumerated() {
            for i in 0..<perLeaf {
                let stem = "\(rng.pick(words))_\(rng.pick(words))\(li * perLeaf + i)"
                if li * perLeaf + i == 12_345 { sample = stem }
                try touch(leaf.appendingPathComponent("\(stem).\(rng.pick(exts))").path, nil)
            }
        }

        // Content corpus: small source and text files with known lines.
        let src = root.appendingPathComponent("src")
        let langs: [(ext: String, def: (Int) -> String)] = [
            ("rs", { "pub fn heron_\($0)(x: u32) -> u32 {\n    x + \($0)\n}\n" }),
            ("swift", { "func heron\($0)(_ x: Int) -> Int {\n    x + \($0)\n}\n" }),
            ("py", { "def heron_\($0)(x):\n    return x + \($0)\n" }),
            ("md", { "# Heron \($0)\n" }),
            ("txt", { "heron \($0)\n" }),
        ]
        for i in 0..<textFiles {
            let dir = src.appendingPathComponent("pkg\(i % 40)/mod\(i % 7)")
            if i < 280 { try mkdir(dir) }  // 40 × 7 distinct folders
            let lang = langs[i % langs.count]
            var body = "// generated fixture \(i)\n"
            body += lang.def(i)
            for l in 0..<20 {
                body += "\(rng.pick(words)) \(rng.pick(words)) \(rng.pick(words)) line \(l)\n"
            }
            if i % 10 == 0 { body += "the quantum lattice holds\n" }  // literal: 200 files
            if i % 25 == 0 { body += "fsbench needle_\(i)7 marker\n" }  // regex: 80 files
            try touch(dir.appendingPathComponent("file\(i).\(lang.ext)").path, body)
        }
        return (nameFiles + textFiles, dirs, sample)
    }
}

/// The real daemon, isolated in a temp HOME with FSEARCH_ROOT on the fixture.
final class DaemonRun: @unchecked Sendable {
    let home: URL
    let root: URL
    let process = Process()
    var socketPath: String { home.path + "/Library/Application Support/FSearch/fsearch.sock" }
    let pidFile: URL

    init(binary: URL, home: URL, root: URL, pidFile: URL) {
        (self.home, self.root, self.pidFile) = (home, root, pidFile)
        process.executableURL = binary
        process.arguments = ["serve"]
        process.environment = ["HOME": home.path, "FSEARCH_ROOT": root.path, "PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Like the bench itself, keep the daemon off efficiency cores on a busy Mac.
        process.qualityOfService = .userInteractive
    }

    func start() throws {
        try process.run()
        try? "\(process.processIdentifier)\n".write(to: pidFile, atomically: true, encoding: .utf8)
        Cleanup.shared.daemonPid = process.processIdentifier
    }

    /// Terminate, wait up to 5 s, then SIGKILL.
    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<50 where process.isRunning { usleep(100_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        Cleanup.shared.daemonPid = nil
        try? FileManager.default.removeItem(at: pidFile)
    }
}

/// Last-resort cleanup on SIGINT/SIGTERM: kill the daemon, delete the temp tree.
final class Cleanup: @unchecked Sendable {
    static let shared = Cleanup()
    private let lock = NSLock()
    private var _pid: pid_t?
    private var _dirs: [URL] = []
    private var sources: [DispatchSourceSignal] = []

    var daemonPid: pid_t? {
        get { lock.lock(); defer { lock.unlock() }; return _pid }
        set { lock.lock(); _pid = newValue; lock.unlock() }
    }

    func removeLater(_ u: URL) { lock.lock(); _dirs.append(u); lock.unlock() }

    func runNow() {
        lock.lock(); let pid = _pid; let dirs = _dirs; _pid = nil; _dirs = []; lock.unlock()
        if let pid {
            kill(pid, SIGTERM)
            for _ in 0..<50 { if kill(pid, 0) != 0 { break }; usleep(100_000) }
            kill(pid, SIGKILL)
        }
        for d in dirs { try? FileManager.default.removeItem(at: d) }
    }

    func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            s.setEventHandler { [self] in
                FileHandle.standardError.write(Data("\nFSearchBench: signal \(sig), cleaning up\n".utf8))
                runNow()
                exit(128 + sig)
            }
            s.resume()
            sources.append(s)
        }
    }
}

@MainActor func benchDaemon(_ b: Bench, binary: URL, work: URL) async throws {
    let c = b.config
    // Real path (no /tmp symlink): the daemon content-indexes only under HOME, compared by real path.
    // (Foundation's resolvingSymlinksInPath maps /private/tmp back to /tmp, so use realpath.)
    let real =
        realpath(work.path, nil).map { p in
            defer { free(p) }; return URL(fileURLWithPath: String(validatingCString: p) ?? work.path)
        } ?? work
    let base = real.appendingPathComponent("d", isDirectory: true)
    let home = base.appendingPathComponent("h", isDirectory: true)
    // The daemon only content-indexes files under HOME, so the tree lives inside it.
    let root = home.appendingPathComponent("root", isDirectory: true)
    Cleanup.shared.removeLater(base)
    defer { try? FileManager.default.removeItem(at: base) }
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

    let t0 = now()
    let built = try FixtureTree.build(at: root)
    let genMs = Double(now() - t0) / 1e6
    print(
        "  fixture: \(built.files) files, \(built.dirs) dirs in \(String(format: "%.0f", genMs)) ms (seed \(String(FixtureTree.seed, radix: 16)))"
    )

    let pidFile = work.appendingPathComponent("daemon.pid")
    let dataDir = home.appendingPathComponent("Library/Application Support/FSearch")

    /// Launch to "every fixture file is in the name index", polling every 5 ms.
    func namesReady(_ d: DaemonRun, _ client: DaemonClient, launched: UInt64) async throws -> (DaemonStatus, Double) {
        let deadline = launched + 180 * 1_000_000_000
        while now() < deadline {
            guard d.process.isRunning else { throw BenchError("daemon exited during indexing (status \(d.process.terminationStatus))") }
            if let s = try? await client.status(), s.entries >= built.files, (try? await client.search("heron_lattice", limit: 1)) != nil {
                return (s, Double(now() - launched))
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw Inconclusive("daemon name index not ready after 180 s")
    }

    // Name index build time is a ~50 ms single shot, so take it from several
    // cold starts: each run gets a fresh data folder (the fixture stays).
    var buildNs: [Double] = []
    if c.wants("index.build.names") {
        for _ in 0..<4 {
            let d = DaemonRun(binary: binary, home: home, root: root, pidFile: pidFile)
            let launched = now()
            try d.start()
            defer { d.stop(); try? FileManager.default.removeItem(at: dataDir) }
            buildNs.append(try await namesReady(d, DaemonClient(socketPath: d.socketPath, timeout: 30), launched: launched).1)
        }
    }

    let d = DaemonRun(binary: binary, home: home, root: root, pidFile: pidFile)
    defer { d.stop() }
    let launched = now()
    try d.start()
    let client = DaemonClient(socketPath: d.socketPath, timeout: 30)
    let deadline = launched + 180 * 1_000_000_000
    let (namesStatus, namesNs) = try await namesReady(d, client, launched: launched)
    buildNs.append(namesNs)

    // Content ready: nothing pending and the literal query finds its files.
    var contentStatus: DaemonStatus?
    var lastLog = now()
    while now() < deadline {
        let s = try? await client.status()
        let g = try? await client.grep(q: "", pattern: "quantum lattice", mode: .literal)
        if let s, s.contentPending == 0, s.contentDocs >= FixtureTree.textFiles, let g, g.complete, !g.files.isEmpty {
            contentStatus = s; break
        }
        if now() - lastLog > 5_000_000_000 {
            lastLog = now()
            print(
                "  waiting for content index: \(s.map { "docs \($0.contentDocs), pending \($0.contentPending), segments \($0.contentSegments)" } ?? "no status"); grep \(g.map { "\($0.files.count) files, complete \($0.complete), source \($0.source)" } ?? "failed")"
            )
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    guard let cs = contentStatus else { throw Inconclusive("daemon content index not ready after 180 s") }
    let contentMs = Double(now() - launched) / 1e6

    if b.config.wants("index.build.names") {
        b.add(
            stats(
                "index.build.names", .tracked, perOp: buildNs, ops: 1,
                info: ["entries": "\(namesStatus.entries)", "dirs": "\(namesStatus.dirs)", "cold_starts": "\(buildNs.count)"]))
    }
    b.track(
        "index.build.content", value: contentMs * 1e6, unit: "ns",
        info: ["contentDocs": "\(cs.contentDocs)", "contentSegments": "\(cs.contentSegments)"])
    b.track("index.bytes.names", value: Double(cs.indexBytes), unit: "bytes")
    b.track("index.bytes.content", value: Double(cs.contentBytes), unit: "bytes")

    let w = c.daemonWarmup, n = c.daemonSamples
    let names: [(String, String)] = [
        ("daemon.search.short", "her"),
        // A whole generated file name: long, and it must hit.
        ("daemon.search.long", built.sample),
        // The same name with two letters swapped: a near miss.
        ("daemon.search.typo", typo(built.sample)),
        ("daemon.search.ext", "heron ext:rs"),
    ]
    for (metric, q) in names {
        var hits = 0
        var took: [UInt64] = []
        try await b.measureAsync(
            metric, group: .daemon, warmup: w, samples: n,
            info: { ["q": q, "hits": "\(hits)", "daemon_took_us_median": "\(median(took))"] }
        ) {
            let r = try await client.search(q, limit: 50)
            hits = r.hits.count
            took.append(r.tookUs)
        }
    }
    let greps: [(String, String, GrepMode)] = [
        ("daemon.grep.literal", "quantum lattice", .literal),
        ("daemon.grep.regex", #"needle_[0-9]+7\b"#, .regex),
        ("daemon.grep.symbol", "heron_12", .symbol),
    ]
    for (metric, p, mode) in greps {
        var files = 0
        var complete = true
        var took: [UInt64] = []
        // Content search fans out over the daemon's thread pool, so other work
        // on the machine moves it more than name search: wider tolerance.
        try await b.measureAsync(
            metric, group: .daemon, warmup: w, samples: n, tolerance: 0.50,
            info: { ["pattern": p, "files": "\(files)", "complete": "\(complete)", "daemon_took_us_median": "\(median(took))"] }
        ) {
            let r = try await client.grep(q: "", pattern: p, mode: mode)
            files = r.files.count
            complete = complete && r.complete
            took.append(r.tookUs)
        }
    }
    try await b.measureAsync("daemon.status", group: .daemon, warmup: w, samples: n) {
        blackHole(try await client.status())
    }
}

/// Swap the 2nd and 3rd characters ("heron" -> "hreon").
func typo(_ s: String) -> String {
    var c = Array(s)
    if c.count > 3 { c.swapAt(1, 2) }
    return String(c)
}

func median(_ xs: [UInt64]) -> UInt64 {
    guard !xs.isEmpty else { return 0 }
    return xs.sorted()[xs.count / 2]
}
