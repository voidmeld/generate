# Benchmarks

Measure execution time after you change the execution path.
The Verify `Benchmark.case` in `bench/simple-path.luau` measures one stage with no artifacts.
It warms up and keeps 15 raw samples. It sets no time budget.
It excludes provider, file, process, engine, network, review and publication time.

## Run it

Run `lute run tools/gate.luau --benchmark --only benchmark`.
The default gate does not select the benchmark.
Use `lute run tools/benchmark.luau` to print the sample count, p50 and p95.

## Store and compare runs

1. Run `lute run tools/benchmark.luau --out before.json` before the change.
2. Run `lute run tools/benchmark.luau --out after.json` after the change.
3. Run `lute run tools/benchmark.luau --compare before.json after.json`.

`--out` stores the run with `Benchmark.store` and `Lute.encode`.
`--compare` calls `Benchmark.compare` on two stored runs.
A comparison fails if p50 exceeds both limits: 1.25 times the baseline and the baseline plus 20 microseconds.

Compare runs on the same host and under the same load.
Record the commands and stored files in the change report.
Investigate repeated increases. Keep stored runs outside the active source.
One result does not prove a speed increase or predict production throughput.
