# Benchmarks

After you change the execution hot path, measure it.
The benchmark is one `Benchmark.case` of the Verify testing library. It is in `bench/simple-path.luau`.
It warms up, keeps 15 raw samples and measures one stage of framework work with zero artifacts.
It excludes provider, filesystem, subprocess, engine, network, review and publication time.
It declares no budget, so a run only measures.

## Run it

- In the gate: `lute run tools/gate.luau --benchmark --only benchmark`. The producer has the tier `benchmark`.
  The default gate does not include it.
- By itself: `lute run tools/benchmark.luau`. It prints the sample count and the p50 and p95 values.

## Store and compare runs

1. Run `lute run tools/benchmark.luau --out before.json` before your change.
2. Run `lute run tools/benchmark.luau --out after.json` after your change.
3. Run `lute run tools/benchmark.luau --compare before.json after.json`.

`--out` stores the run with `Benchmark.store` and writes it with `Lute.encode`.
`--compare` reads two stored runs and calls `Benchmark.compare`. A run fails when its p50 is above both 1.25 times the baseline and the baseline plus 20 microseconds.

- Compare runs on the same host and under the same load.
- Report the commands and the stored files with the candidate.
- Investigate sustained regressions.
- One measurement does not establish a speedup. It does not predict asset-production throughput.
- Keep stored runs outside the active source.
