import Foundation

/// bench/baseline.json: one entry per machine key. Baselines are only
/// comparable on the machine (or CI image) that recorded them.
struct BaselineFile: Codable {
    var schema = 1
    var note =
        "Machine-specific. Update with scripts/bench.sh --record; tolerances may be tuned per metric by hand and survive re-recording."
    var machines: [String: BaselineEntry] = [:]
}

struct BaselineEntry: Codable {
    var provisional: Bool
    var recorded: String
    var machine: MachineInfo
    var metrics: [String: BaselineMetric]
}

struct BaselineMetric: Codable {
    var group: Group
    var unit: String
    var median: Double
    var p95: Double
    var min: Double
    var tolerance: Double
}

enum Baseline {
    static func load(_ url: URL) throws -> BaselineFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return BaselineFile() }
        return try JSONDecoder().decode(BaselineFile.self, from: Data(contentsOf: url))
    }

    static func loadRun(_ url: URL) throws -> RunResult {
        try JSONDecoder().decode(RunResult.self, from: Data(contentsOf: url))
    }

    static func write<T: Encodable>(_ v: T, to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        var d = try enc.encode(v)
        d.append(UInt8(ascii: "\n"))
        try d.write(to: url, options: .atomic)
    }

    /// Replace this machine's entry with `run`, keeping hand-tuned tolerances.
    static func record(baseline url: URL, run: RunResult, key: String, provisional: Bool) throws {
        var file = try load(url)
        let old = file.machines[key]?.metrics ?? [:]
        var metrics: [String: BaselineMetric] = [:]
        for m in run.metrics {
            metrics[m.name] = BaselineMetric(
                group: m.group, unit: m.unit, median: m.median, p95: m.p95, min: m.min,
                tolerance: old[m.name]?.tolerance ?? m.tolerance)
        }
        file.machines[key] = BaselineEntry(provisional: provisional, recorded: run.date, machine: run.machine, metrics: metrics)
        try write(file, to: url)
        print("recorded \(metrics.count) metrics for \(key)\(provisional ? " (provisional)" : "") in \(url.path)")
    }

    enum Outcome: Int32 { case pass = 0, regressed = 1, noBaseline = 2 }

    /// Print a comparison table; return the regressed metric names, and
    /// whether the canary says the machine was busy during the run.
    static func compare(baseline url: URL, run: RunResult, key: String) throws -> (Outcome, [String], Bool) {
        let file = try load(url)
        guard let entry = file.machines[key] else {
            print("no baseline for machine \"\(key)\" in \(url.lastPathComponent): report only")
            return (.noBaseline, [], false)
        }
        print("baseline: \(key), recorded \(entry.recorded)\(entry.provisional ? " (PROVISIONAL)" : "")")
        print(
            Table.pad("metric", 34) + Table.pad("baseline", 12, right: true) + Table.pad("now", 12, right: true)
                + Table.pad("delta", 9, right: true) + Table.pad("tol", 7, right: true) + "  status")
        var regressed: [String] = []
        var busy = false
        for m in run.metrics {
            guard let b = entry.metrics[m.name] else {
                print(
                    Table.pad(m.name, 34) + Table.pad("–", 12, right: true) + Table.pad(Table.fmt(m.median, m.unit), 12, right: true)
                        + "                  new")
                continue
            }
            let delta = b.median > 0 ? m.median / b.median - 1 : 0
            let over = delta > b.tolerance
            let canary = m.group == .canary
            if over && canary { busy = true }
            if over && !canary { regressed.append(m.name) }
            let status =
                over
                ? (canary ? "BUSY (machine slower than at baseline)" : "REGRESSED")
                : (delta < -b.tolerance ? "faster" : "ok")
            print(
                Table.pad(m.name, 34) + Table.pad(Table.fmt(b.median, b.unit), 12, right: true)
                    + Table.pad(Table.fmt(m.median, m.unit), 12, right: true)
                    + Table.pad(String(format: "%+.1f%%", delta * 100), 9, right: true)
                    + Table.pad(String(format: "%.0f%%", b.tolerance * 100), 7, right: true) + "  " + status)
        }
        let missing = Set(entry.metrics.keys).subtracting(run.metrics.map(\.name))
        if !missing.isEmpty && run.config["filter"] == "" {
            print("not measured this run: \(missing.sorted().joined(separator: ", "))")
        }
        return (regressed.isEmpty ? .pass : .regressed, regressed, busy)
    }
}
