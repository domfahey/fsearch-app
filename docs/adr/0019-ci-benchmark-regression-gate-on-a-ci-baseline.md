# 0019. CI benchmark regression gate on a `ci-macos-26` baseline

Date: 2026-11-24
Status: Accepted

## Context

`scripts/bench.sh` measures in-process work, daemon queries and index builds, and compares them to `bench/baseline.json`, which is keyed by machine. CI ran it with `--report-only` and `continue-on-error`, so a slowdown could not fail a build. Hosted runners are noisy, so the numbers from a developer's Mac do not apply to them.

## Considered options

- Keep CI report-only. No noise, but regressions are found by hand.
- Gate against the developer Mac's baseline. Hosted runners are slower, so the gate fails at random.
- Record a `ci-macos-26` baseline from CI runs and gate against it, with per-metric tolerances. This is the choice below.

## Decision

- `bench/baseline.json` has a `ci-macos-26` entry, the per-metric median of five `macos-26` CI runs. The `bench` job in `.github/workflows/ci.yml` sets `BENCH_MACHINE: ci-macos-26` and runs `scripts/bench.sh` without `--report-only`.
- Tolerances are set per metric from the observed spread, from 10% (index bytes) to 85% (daemon queries and status). Every non-canary metric still fails a 2x slowdown.
- A metric fails (exit 1) only if it regresses on the run and again on a re-run. If the CPU canary shows a slow machine, the script waits and retries, then exits 75.
- CI turns exit 75 into a `::warning::` and passes. Exit 1 fails the job.

## Consequences

- A real regression fails CI, and runner noise does not.
- A busy runner can hide a regression for one run, because exit 75 passes.
- The baseline must be re-recorded when the runner image, Xcode or the daemon changes enough to move the numbers, using CI's `bench-results` artifact (`swift run -c release --package-path Packages/FSearchKit FSearchBench record --baseline bench/baseline.json --current <file> --machine ci-macos-26`). See [bench/README.md](../../bench/README.md).
