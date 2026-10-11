# Benchmarks

`scripts/bench.sh` builds `FSearchBench` (an executable target in
`Packages/FSearchKit`, release build), runs it, writes the results as JSON and
compares them with this machine's entry in `bench/baseline.json`.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
scripts/build-daemon.sh            # once, for the daemon end-to-end metrics
scripts/bench.sh                   # run + regression check (exit 1 on a regression)
scripts/bench.sh --record          # run + rewrite this machine's baseline entry
scripts/bench.sh --self-test       # simulate a 2x slowdown: must exit 1
scripts/bench.sh --skip-daemon     # in-process metrics only (no Vendor/fsearch needed)
scripts/bench.sh --filter daemon.grep,decode   # metrics whose names start with these
scripts/bench.sh --report-only     # compare, but never fail (CI)
```

A full run takes about 20 s. Results land in `bench/results/<UTC time>-<machine>.json`
(git-ignored) and as a table on stdout.

## What's measured

Each metric reports median, p95, min and mean over N samples after warm-up.
Times are per operation (stored in ns, shown as ns/µs/ms).

| Metric | What |
| --- | --- |
| `keystroke.split.{plain,filters,quoted}` | `QuerySplit.split` on a plain query, one with four filters, one with quoted words |
| `keystroke.contentSearch` | `QuerySplit.contentSearch` (`grep:` detection, run on every names-mode keystroke) |
| `keystroke.panelRows.50` | `PanelRows.count` + `row(at:)` for every row of a 50-result list |
| `keystroke.panelKeys.reduce10` | `PanelState.reduce(_:_:)` over a 10-key burst |
| `decode.search50`, `decode.grep50` | `DaemonClient.decodeReply` of a 50-hit `SearchReply` and a 50-file (3 lines each) `GrepReply` |
| `searchlog.append.10k` | `SearchLog.append` onto a 10,000-line log (file reset before each sample) |
| `searchlog.entries.10k` | `SearchLog.entries()` reading a 10,000-line log |
| `debugformat.row` | `DebugFormat.daemonMs` + `roundTrip` + `bytes` (one log row) |
| `debugformat.shown.10k` | `DebugFormat.shown` filtering 10,000 records |
| `client.search50`, `client.grep50` | `DaemonClient` round trip against an in-process canned socket server (client + socket overhead only) |
| `model.refresh.burst100` | 100 rapid `SearchModel.refresh` calls (latest wins) against an instant stub backend, until all return |
| `model.refresh.single` | one `SearchModel.refresh` against the stub |
| `index.build.names` | real daemon: launch until every fixture file is in the name index; median of 5 cold starts (fresh data folder each) |
| `index.build.content` | real daemon: launch until the content index has nothing pending (single sample; mostly the daemon's debounce timers) |
| `index.bytes.names` / `index.bytes.content` | `status.index_bytes` / `status.content_bytes` after indexing |
| `daemon.search.{short,long,typo,ext}` | real daemon name search: `her`, a whole generated file name, the same name with two letters swapped, `heron ext:rs` |
| `daemon.grep.{literal,regex,symbol}` | real daemon content search: `quantum lattice`, `needle_[0-9]+7\b`, symbol `heron_12` |
| `daemon.status` | real daemon `status` round trip |
| `canary.cpu`, `canary.parallel` | fixed integer loop on one thread / on every core: machine-load detectors, never counted as regressions |

The daemon metrics run `Vendor/fsearch serve` (or `$FSEARCH_DAEMON`) with a
temp `HOME` and `FSEARCH_ROOT=$HOME/root` under a fresh `/tmp/fsb.*` directory
(the daemon only content-indexes under `HOME`). The tree is generated with a
fixed seed: 50,000 empty files across 1,000 nested folders plus 2,000 small
source/text files with known lines (definitions `heron_<i>`, "the quantum
lattice holds" in every 10th, `fsbench needle_<i>7` in every 25th). The bench
waits until `status` shows every file indexed and the content index has nothing
pending, then measures. The daemon is always stopped (SIGTERM, SIGKILL after
5 s) and the tree deleted, on success, failure or Ctrl-C (Swift `defer` plus a
signal handler, and a `trap` in `bench.sh`). It never touches
`~/Library/Application Support/FSearch` or the real index. Hit counts are kept
in each metric's `info` so a query that silently stops matching shows up.

Each results file records the machine: chip, model, cores, macOS, Xcode,
Swift, the daemon revision (`Vendor/fsearch.rev`, else the pin in
`scripts/build-daemon.sh`) and the 1-minute load average at start.

## Regression check

A metric regresses when its median is slower than the baseline median by more
than its tolerance. Regressed metrics are re-run (`--filter`); the check fails
(exit 1) only for metrics that regress on both runs, so a one-off burst of
background load doesn't fail it.

Every run also measures two canaries that no FSearch change can affect (and
that `--self-test` doesn't slow), at its start and end: `canary.cpu`, a fixed
integer loop on one thread, and `canary.parallel`, the same loop on every core
at once (it slows when other work takes cores away, which is what moves the
daemon's multi-threaded content search). If the re-run still regresses while a
canary is beyond its tolerance, the machine is busy, not the code: the script
waits 30 s and re-runs, up to three times, then exits 75 ("inconclusive")
instead of 1.

Exit codes: 0 pass (or no baseline for this machine, or `--report-only`),
1 regression, 75 inconclusive (machine stayed busy, or the daemon was too slow),
anything else an error.

Slow machines: a daemon round trip that times out is retried once; a second
timeout (or an index not ready within 180 s) marks that metric "inconclusive
(daemon slow)", skips it and keeps the rest of the run (listed in the result's
`config.inconclusive`). Client timeouts are generous (30 s for the daemon, 15 s
for the in-process stub). With `--report-only` the script always exits 0 after
writing whatever results it got.

Default tolerances (stored per metric in `baseline.json`; edit one by hand to
tune it, and `--record` keeps your value):

| Group | Tolerance | Why |
| --- | --- | --- |
| in-process (`keystroke.*`, `decode.*`, `searchlog.entries.10k`, `debugformat.*`, `client.*`, `model.*`) | +20% | run-to-run spread is under 10% even with other builds running |
| `searchlog.append.10k` | +50% | file I/O per append; moved by other processes' disk activity (seen +19% to +40% on a busy machine) |
| daemon name search and status (`daemon.search.*`, `daemon.status`) | +35% | sub-millisecond round trips to another process; scheduler noise |
| daemon content search (`daemon.grep.*`) | +50% | fans out over the daemon's thread pool, so it moves most with load on other cores |
| index build time (`index.build.*`) | +50% | few samples per run (5 cold starts for names, 1 for content) |
| index size (`index.bytes.*`) | +10% | deterministic for a fixed tree and daemon revision |
| `canary.cpu` / `canary.parallel` | +15% / +25% | beyond this the run is flagged busy (see above) |

Both the bench and the daemon it launches run at user-interactive QoS, so a
busy Apple Silicon Mac keeps them on performance cores; at default QoS, load
from other work pushed in-process medians up 20-100% by landing them on
efficiency cores. Even so, record baselines on a quiet machine: content search
medians still varied up to 2x between runs while other builds and test suites
were running.

`--self-test` makes every measured operation run twice (a real 2x slowdown,
not an edited number); the check must report regressions on both runs and
exit 1.

## Baselines are machine-specific

`baseline.json` holds one entry per machine key: `hw.model` plus the chip
(e.g. `Mac17,7-apple-m5-max`), or `$BENCH_MACHINE` if set. A run compares only
against its own machine's entry; with no entry it reports and exits 0.
An entry marked `"provisional": true` was recorded on a busy machine and should
be re-recorded when it's quiet.

To update the baseline after an intended change (or on a new machine): close
other heavy work, run `scripts/bench.sh --record`, check the numbers, then
`scripts/bench.sh` twice to confirm it passes against itself, and commit
`bench/baseline.json`. Re-record after bumping the daemon pin, since the
daemon metrics move with it.

## CI

The `bench` job in `.github/workflows/ci.yml` runs `scripts/bench.sh
--report-only` with `BENCH_MACHINE=ci-macos-26` and uploads `bench/results/*.json`
as the `bench-results` artifact. It is `continue-on-error` and never fails the
workflow. It also sets `FSEARCH_BENCH_TIMEOUT=90`: the seconds one daemon request
may take before the run gives up. It replaces the local defaults (15 s for the
canned server, 30 s for the real daemon) and works the same way locally.
There is no `ci-macos-26` entry yet, so it only reports; to add one,
take the JSON from a CI artifact and run
`swift run -c release --package-path Packages/FSearchKit FSearchBench record --baseline bench/baseline.json --current <file> --machine ci-macos-26`.
Hosted runners vary between runs, so treat CI numbers as a trend.
