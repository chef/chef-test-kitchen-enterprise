# Ex6 Performance Baseline

## Scope
- Function benchmarked: `Kitchen::Verifier::Dummy#call`
- Benchmark script: `ai-track-docs/benchmarks/verifier-dummy-call-benchmark.rb`
- Mode: success path (`sleep: 0`, `random_failure: false`)

## Run Command
```bash
bundle exec ruby ai-track-docs/benchmarks/verifier-dummy-call-benchmark.rb
```

## Baseline Results
- Run date: 2026-05-23
- Iterations per repeat: 10000
- Repeats: 7
- Mean: 113.305 ms
- Stddev: 5.495 ms
- Min: 109.759 ms
- Max: 126.440 ms
- Per-call mean: 11.331 us
- Raw samples (ms): 126.440, 110.501, 112.896, 109.759, 112.949, 110.237, 110.355

## Variance Notes
- Micro-benchmarks are sensitive to CPU scheduler noise, thermal throttling, and background load.
- Ruby JIT settings, GC timing, and process startup overhead can shift measurements.
- Treat this baseline as relative guidance for future comparisons, not an absolute SLA.
- The first sample was the highest in this run, which is consistent with warm-up effects.
