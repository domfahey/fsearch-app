import Darwin
import FSearchKit
import Foundation

// FSearchBench: performance benchmarks for FSearchKit and the bundled daemon.
// Normally run through scripts/bench.sh, which builds in release, picks the
// output path and compares against bench/baseline.json.
//
//   FSearchBench run [--out F] [--machine KEY] [--daemon PATH] [--daemon-rev R] [--xcode S]
//                    [--work DIR] [--filter a,b] [--skip-daemon] [--self-test] [--report-only] [--samples N]
//   FSearchBench compare --baseline F --current F --machine KEY [--regressed-out F] [--busy-out F]
//   FSearchBench record  --baseline F --current F --machine KEY [--provisional]
//   FSearchBench machine-key

func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "unknown" }
    return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

func machineKey() -> String {
    if let k = ProcessInfo.processInfo.environment["BENCH_MACHINE"], !k.isEmpty { return k }
    let chip = sysctlString("machdep.cpu.brand_string").lowercased()
        .map { $0.isLetter || $0.isNumber ? $0 : "-" }
    return "\(sysctlString("hw.model"))-\(String(chip))".replacingOccurrences(of: "--", with: "-")
}

struct Args {
    var command: String
    var opts: [String: String] = [:]
    var flags: Set<String> = []
    init(_ argv: [String]) {
        command = argv.first ?? "run"
        var i = 1
        while i < argv.count {
            let a = argv[i]
            if a.hasPrefix("--"), i + 1 < argv.count, !argv[i + 1].hasPrefix("--"),
               !["--skip-daemon", "--self-test", "--provisional", "--report-only"].contains(a) {
                opts[String(a.dropFirst(2))] = argv[i + 1]; i += 2
            } else {
                flags.insert(String(a.dropFirst(2))); i += 1
            }
        }
    }
    func need(_ k: String) -> String {
        guard let v = opts[k] else { fail("missing --\(k)") }
        return v
    }
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("FSearchBench: \(msg)\n".utf8))
    exit(64)
}

setvbuf(stdout, nil, _IOLBF, 0)
// Ask for performance cores: at default QoS a busy Apple Silicon Mac may run the
// bench on efficiency cores, which reads as a 1.5-2x "regression".
pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
let args = Args(Array(CommandLine.arguments.dropFirst()))

switch args.command {
case "machine-key":
    print(machineKey())

case "compare":
    let run = try Baseline.loadRun(URL(fileURLWithPath: args.need("current")))
    let (outcome, regressed, busy) = try Baseline.compare(baseline: URL(fileURLWithPath: args.need("baseline")), run: run,
                                                          key: args.opts["machine"] ?? run.machine.key)
    if let out = args.opts["regressed-out"] {
        try (regressed.joined(separator: "\n") + (regressed.isEmpty ? "" : "\n")).write(toFile: out, atomically: true, encoding: .utf8)
    }
    if let out = args.opts["busy-out"] {
        try (busy ? "busy\n" : "").write(toFile: out, atomically: true, encoding: .utf8)
    }
    exit(outcome.rawValue)

case "record":
    let run = try Baseline.loadRun(URL(fileURLWithPath: args.need("current")))
    try Baseline.record(baseline: URL(fileURLWithPath: args.need("baseline")), run: run,
                        key: args.opts["machine"] ?? run.machine.key, provisional: args.flags.contains("provisional"))

case "run":
    var config = BenchConfig()
    if let f = args.opts["filter"] { config.filter = f.split(separator: ",").map(String.init) }
    if args.flags.contains("self-test") { config.slowdown = 2 }
    if let s = args.opts["samples"], let n = Int(s) { config.samples = n; config.daemonSamples = n }

    let key = args.opts["machine"] ?? machineKey()
    var load = [Double](repeating: 0, count: 3)
    getloadavg(&load, 3)
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let machine = MachineInfo(
        key: key, model: sysctlString("hw.model"), chip: sysctlString("machdep.cpu.brand_string"),
        cores: ProcessInfo.processInfo.activeProcessorCount,
        macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
        xcode: args.opts["xcode"] ?? "unknown", swift: args.opts["swift"] ?? "unknown",
        daemonRev: args.opts["daemon-rev"] ?? "unknown", loadAverage1m: load[0])

    // Work dir: short path (Unix socket paths are limited to 104 bytes).
    let work: URL
    let ownWork: Bool
    if let w = args.opts["work"] {
        work = URL(fileURLWithPath: w, isDirectory: true); ownWork = false
    } else {
        var tmpl = Array("/private/tmp/fsb.XXXXXX".utf8CString)
        guard mkdtemp(&tmpl) != nil else { fail("mkdtemp failed") }
        work = URL(fileURLWithPath: String(decoding: tmpl.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self), isDirectory: true); ownWork = true
    }
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    if ownWork { Cleanup.shared.removeLater(work) }
    Cleanup.shared.installSignalHandlers()
    defer { Cleanup.shared.runNow() }

    print("FSearchBench on \(machine.chip) (\(machine.model), \(machine.cores) cores), macOS \(machine.macOS), \(machine.xcode)")
    print("daemon rev \(machine.daemonRev); load average \(String(format: "%.2f", load[0])); machine key \(key)")
    if config.slowdown > 1 { print("SELF-TEST: every measured operation runs \(config.slowdown)× (simulated slowdown)") }
    print(Table.header)
    let bench = Bench(config: config)
    var failure: Error?
    bench.canary(final: false)
    await benchKeystroke(bench, work: work)
    do { try await benchClient(bench, work: work) } catch { failure = error }

    let daemonWanted = config.filter.isEmpty || config.filter.contains { "daemon.".hasPrefix($0) || $0.hasPrefix("daemon") || $0.hasPrefix("index") }
    if failure == nil, daemonWanted, !args.flags.contains("skip-daemon") {
        let bin = args.opts["daemon"].map { URL(fileURLWithPath: $0) }
        if let bin, FileManager.default.isExecutableFile(atPath: bin.path) {
            do { try await benchDaemon(bench, binary: bin, work: work) } catch { failure = error }
        } else {
            print("daemon benchmarks skipped: no daemon binary (pass --daemon; run scripts/build-daemon.sh)")
        }
    }

    // A slow machine is not a failure: a daemon that never became ready or
    // answered in time (after one retry) yields an inconclusive result.
    if let f = failure, f is Inconclusive || (f as? DaemonError) == .timeout {
        bench.markInconclusive("daemon benchmarks", "\(f)")
        failure = nil
    }
    bench.canary(final: true)
    let fmt = ISO8601DateFormatter()
    let result = RunResult(date: fmt.string(from: Date()), machine: machine,
                           config: ["samples": "\(config.samples)", "daemonSamples": "\(config.daemonSamples)",
                                    "warmup": "\(config.warmup)", "slowdown": "\(config.slowdown)",
                                    "filter": config.filter.joined(separator: ","),
                                    "inconclusive": bench.inconclusive.joined(separator: ","),
                                    "retried_timeouts": "\(bench.retries)",
                                    "fixture": "\(FixtureTree.nameFiles)+\(FixtureTree.textFiles) files, seed \(String(FixtureTree.seed, radix: 16))"],
                           metrics: bench.metrics)
    if let out = args.opts["out"] {
        try Baseline.write(result, to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
    if let failure {
        Cleanup.shared.runNow()
        fail("benchmark failed: \(failure)")
    }
    if !bench.inconclusive.isEmpty {
        print("INCONCLUSIVE (daemon slow): not measured: \(bench.inconclusive.joined(separator: ", "))")
        // Exit 75 (like bench.sh) unless the caller only wants a report.
        if !args.flags.contains("report-only") { exit(75) }
    }

default:
    fail("unknown command \(args.command)")
}
