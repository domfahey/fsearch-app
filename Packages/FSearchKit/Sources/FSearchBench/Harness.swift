import Darwin
import FSearchKit
import Foundation

/// Metric groups. Each has its own default regression tolerance.
enum Group: String, Codable, Sendable {
    /// Pure functions and in-process client work: steady, so a tight tolerance.
    case inproc
    /// The real daemon over its socket: disk, scheduler and index noise.
    case daemon
    /// Single-shot tracked numbers (index build time, index size).
    case tracked
    /// A fixed CPU workload that FSearch code can't change: when it is slow,
    /// the machine is busy and the run is noise, not a regression.
    case canary
}

/// One measured metric. Times are in nanoseconds per operation; sizes in bytes.
struct Metric: Codable, Sendable {
    var name: String
    var group: Group
    var unit: String          // "ns" or "bytes"
    var median: Double
    var p95: Double
    var min: Double
    var mean: Double
    var samples: Int
    var opsPerSample: Int
    /// Fractional regression allowed on the median (0.20 = +20%).
    var tolerance: Double
    var info: [String: String]?
}

struct MachineInfo: Codable, Sendable {
    var key: String
    var model: String
    var chip: String
    var cores: Int
    var macOS: String
    var xcode: String
    var swift: String
    var daemonRev: String
    var loadAverage1m: Double
}

struct RunResult: Codable, Sendable {
    var date: String
    var machine: MachineInfo
    var config: [String: String]
    var metrics: [Metric]
}

/// Group defaults, chosen from measured run-to-run variance (see bench/README.md).
/// Individual metrics override them where noted at the call site.
enum Tolerance {
    static func `default`(_ g: Group) -> Double {
        switch g {
        case .inproc: 0.20
        case .daemon: 0.35
        case .tracked: 0.50
        case .canary: 0.15
        }
    }
}

@inline(__always) func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

/// Keeps a value alive so the optimizer can't drop the work that made it.
@inline(never) @_optimize(none) func blackHole<T>(_ x: T) { _ = x }

/// Benchmark settings shared by every metric.
struct BenchConfig: Sendable {
    var warmup = 5
    var samples = 40
    /// Target wall time of one in-process sample; ops per sample are calibrated to it.
    var sampleTargetNs: UInt64 = 2_000_000
    var daemonWarmup = 10
    var daemonSamples = 100
    /// `--self-test`: every measured operation runs this many times, a real
    /// N-fold slowdown that the regression check must catch.
    var slowdown = 1
    var filter: [String] = []

    func wants(_ name: String) -> Bool {
        filter.isEmpty || filter.contains { name.hasPrefix($0) }
    }
}

func stats(_ name: String, _ group: Group, perOp: [Double], ops: Int, unit: String = "ns", tolerance: Double? = nil, info: [String: String]? = nil) -> Metric {
    let s = perOp.sorted()
    let n = s.count
    func q(_ p: Double) -> Double { s[Swift.min(n - 1, Swift.max(0, Int((p * Double(n)).rounded(.up)) - 1))] }
    let median = n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    return Metric(name: name, group: group, unit: unit, median: median, p95: q(0.95), min: s.first ?? 0,
                  mean: s.reduce(0, +) / Double(Swift.max(1, n)), samples: n, opsPerSample: ops,
                  tolerance: tolerance ?? Tolerance.default(group), info: info)
}

@MainActor final class Bench {
    let config: BenchConfig
    private(set) var metrics: [Metric] = []

    init(config: BenchConfig) { self.config = config }

    func add(_ m: Metric) {
        metrics.append(m)
        print(Table.row(m))
        fflush(stdout)
    }

    /// Synchronous op. `setup` runs before each sample, untimed.
    func measure(_ name: String, group: Group = .inproc, ops fixedOps: Int? = nil, tolerance: Double? = nil,
                 setup: (() -> Void)? = nil, _ body: () -> Void) {
        guard config.wants(name) else { return }
        let factor = config.slowdown
        func run(_ k: Int) -> UInt64 {
            let t0 = now()
            for _ in 0..<k { for _ in 0..<factor { body() } }
            return now() - t0
        }
        var ops = fixedOps ?? 1
        if fixedOps == nil {
            setup?()
            // First calls pay one-time costs (formatter caches, page faults); keep them out of calibration.
            for _ in 0..<3 { _ = run(1) }
            // Calibrate: double until one sample takes the target time.
            while ops < 1 << 24 {
                if run(ops) >= config.sampleTargetNs / 2 { break }
                ops *= 2
            }
            ops = Swift.max(1, ops)
        }
        for _ in 0..<config.warmup { setup?(); _ = run(ops) }
        var perOp: [Double] = []
        for _ in 0..<config.samples {
            setup?()
            perOp.append(Double(run(ops)) / Double(ops))
        }
        add(stats(name, group, perOp: perOp, ops: ops, tolerance: tolerance))
    }

    /// Metrics that could not be measured because the daemon answered too slowly
    /// (a timed-out sample is retried once first). Reported, never fatal here.
    private(set) var inconclusive: [String] = []
    private(set) var retries = 0

    func markInconclusive(_ what: String, _ why: String) {
        inconclusive.append(what)
        print("  inconclusive (daemon slow): \(what): \(why)")
    }

    /// Async op, one op per sample (round trips are already micro- to milliseconds).
    /// A daemon timeout is retried once; a second one makes the metric inconclusive
    /// (skipped, run continues) instead of failing the whole benchmark.
    func measureAsync(_ name: String, group: Group, warmup: Int, samples: Int, tolerance: Double? = nil,
                      info: (() -> [String: String]?)? = nil, _ body: () async throws -> Void) async throws {
        guard config.wants(name) else { return }
        let factor = config.slowdown
        func once() async throws {
            do { try await body() } catch DaemonError.timeout {
                retries += 1
                try await body()
            }
        }
        do {
            for _ in 0..<warmup { try await once() }
            var perOp: [Double] = []
            for _ in 0..<samples {
                let t0 = now()
                for _ in 0..<factor { try await once() }
                perOp.append(Double(now() - t0))
            }
            add(stats(name, group, perOp: perOp, ops: 1, tolerance: tolerance, info: info?()))
        } catch DaemonError.timeout {
            markInconclusive(name, "\(DaemonError.timeout.description) (twice in a row)")
        }
    }

    /// The canary: a fixed integer workload, never slowed by --self-test.
    /// Measured at the start and end of the run so a burst of load in either half shows.
    /// `canary.cpu` is one thread; `canary.parallel` runs the same loop on every
    /// core at once, so it slows when other work takes cores away
    /// (which is what moves the daemon's multi-threaded content search).
    private var canarySamples: [Double] = []
    private var parallelSamples: [Double] = []
    func canary(final: Bool) {
        @Sendable func spin() -> UInt64 {
            var x: UInt64 = 0x9E37_79B9_7F4A_7C15
            for i in 0..<200_000 { x = (x ^ (x >> 29)) &* 0xBF58_476D_1CE4_E5B9 &+ UInt64(i) }
            return x
        }
        let cores = ProcessInfo.processInfo.activeProcessorCount
        for _ in 0..<3 { blackHole(spin()) }
        for _ in 0..<15 {
            var t0 = now()
            blackHole(spin())
            canarySamples.append(Double(now() - t0))
            t0 = now()
            DispatchQueue.concurrentPerform(iterations: cores) { _ in blackHole(spin()) }
            parallelSamples.append(Double(now() - t0))
        }
        if final {
            add(stats("canary.cpu", .canary, perOp: canarySamples, ops: 1))
            add(stats("canary.parallel", .canary, perOp: parallelSamples, ops: 1, tolerance: 0.25,
                      info: ["threads": "\(cores)"]))
        }
    }

    /// A single tracked number (index build time or size).
    func track(_ name: String, value: Double, unit: String, info: [String: String]? = nil) {
        guard config.wants(name) else { return }
        add(Metric(name: name, group: .tracked, unit: unit, median: value, p95: value, min: value, mean: value,
                   samples: 1, opsPerSample: 1,
                   // Index size is deterministic for a fixed tree and daemon; build time is one noisy sample.
                   tolerance: unit == "bytes" ? 0.10 : Tolerance.default(.tracked), info: info))
    }
}

enum Table {
    static func fmt(_ v: Double, _ unit: String) -> String {
        if unit == "bytes" {
            if v >= 1_048_576 { return String(format: "%.2f MiB", v / 1_048_576) }
            if v >= 1024 { return String(format: "%.1f KiB", v / 1024) }
            return String(format: "%.0f B", v)
        }
        if v >= 1e6 { return String(format: "%.2f ms", v / 1e6) }
        if v >= 1e3 { return String(format: "%.2f µs", v / 1e3) }
        return String(format: "%.1f ns", v)
    }

    static func pad(_ s: String, _ n: Int, right: Bool = false) -> String {
        let c = s.count
        if c >= n { return s }
        let sp = String(repeating: " ", count: n - c)
        return right ? sp + s : s + sp
    }

    static var header: String {
        pad("metric", 34) + pad("median", 12, right: true) + pad("p95", 12, right: true)
            + pad("min", 12, right: true) + pad("n×ops", 10, right: true)
    }

    static func row(_ m: Metric) -> String {
        pad(m.name, 34) + pad(fmt(m.median, m.unit), 12, right: true) + pad(fmt(m.p95, m.unit), 12, right: true)
            + pad(fmt(m.min, m.unit), 12, right: true) + pad("\(m.samples)×\(m.opsPerSample)", 10, right: true)
    }
}

/// Deterministic PRNG (SplitMix64) so the fixture tree is identical every run.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func pick<T>(_ a: [T]) -> T { a[below(a.count)] }
}

