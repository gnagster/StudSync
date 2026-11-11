# Performance measurements

Measurements from November 2, 2026. These are individual observations, not performance guarantees or battery acceptance results.

## Swift CodeQL

Completed hosted runs used `macos-26`, manual `swift build`, and CodeQL action v4.39.1. The build log has a long interval before its first package-fetch output; the logs do not establish what causes that interval.

| Observation | PR #19 | PR #20 | PR #22, verbose |
| --- | ---: | ---: | ---: |
| Full Swift job | 17m57s | 16m15s | 16m09s |
| Build command to first fetch output | 9m20s | 7m52s | 7m51s |
| First fetch to last resolved working copy | 18.3s | 12.9s | 16.8s |
| Last working copy to “Building for debugging” | 6.5s | 5.2s | 7.3s |
| Build-start output to build completion | 6m07s | 5m53s | 6m01s |

Evidence: [PR #19 Swift job](https://github.com/gnagster/StudSync/actions/runs/41376618591/job/125058147223), [PR #20 Swift job](https://github.com/gnagster/StudSync/actions/runs/41378575155/job/125064133069), [PR #22 verbose Swift job](https://github.com/gnagster/StudSync/actions/runs/41384659213/job/125082732083). Fetch/resolution and build spans are wall-clock log intervals, not package CPU attribution.

An isolated local experiment used Swift 6.3.3, Xcode 26.6, arm64, and the pinned SwiftSoup 2.11.3 / LRUCache 1.3.0 / Swift Atomics 1.3.1 graph. Source resolution used two fresh scratch directories with one initially empty shared package cache. SDK/compiler caches were not cleared. No CodeQL tracer was active locally.

| Local command | Wall time |
| --- | ---: |
| Resolve with empty source cache | 6.41s |
| Resolve in fresh scratch directory using warmed source cache | 0.87s |
| Build Atomics target | 2.15s |
| Build LRUCache target | 3.69s |
| Build SwiftSoup target, preceding dependencies already built | 3.94s |
| Build app, preceding dependencies already built | 8.55s |
| Repeat app build with compiled objects present | 0.55s |

Target commands ran sequentially and include SwiftPM startup; do not interpret them as isolated compiler CPU costs or predict hosted CodeQL runtime from them.

Reproduce source resolution without deleting the developer's caches:

```sh
bench=$(mktemp -d)
/usr/bin/time -p swift package --cache-path "$bench/cache" --scratch-path "$bench/cold" --skip-update resolve
/usr/bin/time -p swift package --cache-path "$bench/cache" --scratch-path "$bench/warm" --skip-update resolve
```

For target comparisons, use `swift build --cache-path "$bench/cache" --scratch-path "$bench/cold" --skip-update --disable-automatic-resolution --target Atomics`, then `LRUCache`, then `SwiftSoup`; omit `--target` for the app and repeat it for the object-warm case. Keep these local timing experiments separate from the traced scan.

**Decision:** source caching saved about 5.5 seconds in this local experiment. Hosted fetch/resolution accounts for roughly 1–2% of the observed job times. Source caching cannot remove the long pre-fetch interval or compilation, and no end-to-end hosted cache improvement has been demonstrated. No cache Action or dependency replacement is added on that evidence. Revisit if registry latency or a controlled hosted comparison establishes a useful gain.

The 0.55-second object-warm build skips compilation and is not a suitable CodeQL optimization. GitHub's [Swift build guidance](https://docs.github.com/en/code-security/tutorials/customize-code-scanning/prepare-code-for-analysis) recommends a clean build and warns that compilation caches can skip extraction. [Built-in dependency caching](https://docs.github.com/en/code-security/concepts/code-scanning/codeql/codeql-for-compiled-languages#about-dependency-caching-for-codeql) is documented for Java, Go and C#, not Swift. Keep the first-party source-archive check and full traced builds. Earlier package pre-resolution also failed to improve measured job time; do not repeat it as an untested speedup.

The completed verbose run still has a 7m51s gap: the command starts at 03:44:24 UTC, the first manifest/compiler output appears at 03:52:15, and fetching starts in that same second. The log cannot separate process startup, manifest compilation/execution, tracer overhead, and buffered output within that gap. Package source fetches themselves report 0.72–2.02 seconds. The run verifies all eight first-party Swift files in the source archive. Verbose logging is diagnostic, not a speedup.

The hosted image is `macos-26-arm64`, while the manifest and application compiler commands target `x86_64`; CodeQL CLI 2.27.3 uses the `osx64` bundle. GitHub's [system requirements](https://codeql.github.com/docs/codeql-overview/system-requirements/) explain that traced builds on Apple Silicon require Rosetta. This makes translated startup/tooling a candidate for a controlled comparison, not a proven cause. A future comparison can explicitly target the app's arm64 architecture using the [documented Swift build option](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages#customizing-swift-compilation-in-a-codeql-analysis-workflow). That would not establish that the SwiftPM host/manifest process runs natively. Do not disable tracing, restore compiled objects, or remove coverage checks to make the timing look better.

## App startup and short process observation

The runtime check found a correctness issue: before the fix, every sampled main-thread stack was inside `AppStore.init → CredentialVault.read → SecItemCopyMatching`, waiting for system Keychain authorization before `NSApplication.run`. A successful process-existence check alone had not proved that the app event loop started.

The fix merged in PR #21 loads saved credentials after initialization and performs blocking reads/writes off the main actor, retaining system authorization. A second sample found the main thread in the normal AppKit event loop and the waiting Keychain call on a background thread. Its later cancellation fix releases login controls while the old request remains blocked; synthetic regressions exercise a new manual login and web-session adoption without stale state updates. An in-flight system request can still finish, and new credential operations wait behind it to preserve save order. No real Keychain entries are changed by these tests.

Three ten-second intervals of the fixed release process, still waiting for Keychain authorization:

| Interval | CPU (% of one core) | Resident memory | Physical footprint | Package idle wakeups | Interrupt wakeups |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.0000% | 61.25 MiB | 16.55 MiB | 0 | 0 |
| 2 | 0.0000% | 61.25 MiB | 16.55 MiB | 0 | 0 |
| 3 | 0.0080% | 61.27 MiB | 16.55 MiB | 0 | 1 |

Method: one-second `sample` traces plus process-only `proc_pid_rusage(RUSAGE_INFO_V0)` snapshots. CPU uses deltas of user/system Mach-time counters converted with `mach_timebase_info`; wakeups are counter deltas. No credentials, course titles, documents, or raw traces are committed. Measurements exclude other processes, including system authorization services.

The traces establish a wait inside Keychain I/O; system dialogs were not inspected. These earlier measurements describe the authorization-waiting state. Do not infer battery life from these counters.

## Authenticated idle after Keychain authorization

The owner subsequently confirmed Keychain authorization and successful sign-in. The same running app was measured without rebuilding, restarting, changing settings or interrupting it. A one-second stack sample finds the main thread in `NSApplication.run` and no `CredentialVault.read`/`SecItemCopyMatching` wait. Only the non-identifying `setupComplete`, `intervalMinutes` and `lastSync` settings were inspected: setup is complete, the interval is 60 minutes, and a successful sync was recorded within the current process lifetime. The hourly timer itself was not forced or observed firing.

Three ten-second intervals after sign-in:

| Interval | CPU (% of one core) | Resident memory | Physical footprint | Package idle wakeups | Interrupt wakeups |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.0000% | 105.61 MiB | 53.92 MiB | 0 | 0 |
| 2 | 0.0000% | 105.59 MiB | 53.03 MiB | 0 | 0 |
| 3 | 0.0020% | 105.59 MiB | 53.03 MiB | 0 | 1 |

Measured artifact: installed release build 0.1.0 (1), built from the PR #25 integration with merged PR #24 packaging. Executable SHA-256: `f2e3950ed1247a083ef421ed6a6d56ea2d53d80a62e6c3e2b21f361d69a3c23a`.

Method: native `proc_pid_rusage(RUSAGE_INFO_V0)` snapshots, actual `mach_absolute_time` intervals of 10.0051, 10.0037 and 10.0060 seconds, and `mach_timebase_info` conversion. CPU percentage is `100 × delta(user + system CPU nanoseconds) / elapsed nanoseconds`; memory is the endpoint counter divided by 1,048,576; wakeups are counter deltas. Before sampling, a temporary native probe calibrated its own converted CPU delta against `clock_gettime(CLOCK_PROCESS_CPUTIME_ID)` during a short busy interval; the ratio was 1.0000 (allowed 0.95–1.05). Process identity/start counters were checked between samples. The probe compiled with `-Wall -Wextra -Werror`; no permanent app instrumentation or sampling timer was added.

This bounded authenticated observation shows no sustained CPU load, package idle wakeups or rising resident memory that warrants a runtime change. It does not establish long-term memory behavior, battery drain, helper-process energy use, sync-load cost, actual sleep/wake recovery, Start at Login registration or visual layout. No course identifiers/names, filenames, credentials, cookies, documents, raw traces or private paths are committed. Keep those remaining developer checks separate; the Keychain authorization blocker is cleared.

## Release-readiness follow-up

On November 2, a later owner-started process was left running throughout the release-readiness work. Its settings still showed setup complete and a 60-minute interval. A second calibrated 30-second observation measured 0.0000%, 0.0000% and 0.0014% of one core, resident memory steady at 44.97 MiB, footprint steady at 53.58 MiB, zero package idle wakeups and one interrupt wakeup. Actual intervals were 10.0102, 10.0027 and 10.0115 seconds. These are a separate process observation, not a memory comparison against the earlier artifact. Its sampled main thread was in the normal AppKit event loop, with no sampled Keychain read wait.

The saved successful-sync timestamp had not advanced after its age exceeded one hour. That timestamp alone does not establish the current in-memory authentication, pause state, next deadline or a timer failure. No owner preferences were changed and no app restart/manual sync was forced. Existing synthetic tests exercise scheduled callback/reconnect and manual/pause behavior; actual hourly firing remains unverified. No runtime fix is justified by this observation alone.

Master runs 41448491189 (native) and 41448493169 (Swift CodeQL) failed before starting steps: GitHub reported hosted macOS ARM runner acquisition/capacity failures. The release-readiness branch moves CodeQL to `macos-15-intel` and explicitly compiles the app for arm64, retaining a clean traced build and first-party source coverage. This is an unmeasured comparison and availability change, not a claimed speedup. The same branch skips both macOS jobs for allowlisted Markdown-only PRs/master pushes via one Linux classification job, and bounds job durations to prevent indefinite runner usage. No new scan schedule or compiled cache is added.

PR #27's first [Intel CodeQL job](https://github.com/gnagster/StudSync/actions/runs/41455737925/job/125311873966) completed successfully in 15m57s (13:45:46–14:01:43 UTC), including all nine first-party Swift sources. It used Swift 6.1.2/Xcode 16.4 and added Sparkle to the dependency graph, so it is not a controlled comparison with the earlier ARM runs. Build command to first manifest output was about 1m45s, then another 2m55s gap preceded Sparkle manifest output. The binary artifact download itself took only 2.67s; caching that artifact is not justified as a substantial speedup. Total traced build reported 585.38s. This run establishes Intel extraction coverage, not an end-to-end improvement.

The same run's native ARM job was cancelled after 15 minutes with zero steps and no runner assigned, repeating the capacity failure. The follow-up changes native/release jobs to Intel too, with explicit `--arch arm64` in the shared release builder and the existing extracted-archive architecture assertion. Native tests and update fixtures execute for the runner host; released apps remain Apple Silicon only. An x86_64 unit-test build succeeded locally, but execution was blocked by this Xcode installation's arm64-only `swiftpm-testing-helper`; this was a local cross-architecture test-loader limitation, not a failed test assertion. Hosted Intel execution was subsequently established as recorded below.

## Long-running process follow-up

The same installed process was still running on November 2 at approximately 16:57 UTC, more than four hours after its start. It had not been restarted or reconfigured by the agent. Its settings recorded a successful sync about 13 minutes earlier, so the earlier hour-old timestamp observation did not establish a persistent stall. The exact trigger (timer versus user action) was not captured. A one-second sample again found the normal AppKit event loop and no sampled Keychain read/write wait.

A calibrated 30-second process-only observation gave:

| Actual interval | CPU (% of one core) | Resident memory | Physical footprint | Package idle wakeups | Interrupt wakeups |
| --- | ---: | ---: | ---: | ---: | ---: |
| 10.0102s | 0.0065% | 42.28 MiB | 55.61 MiB | 0 | 0 |
| 10.0023s | 0.0020% | 42.27 MiB | 55.59 MiB | 0 | 2 |
| 10.0071s | 0.0696% | 47.84 MiB | 55.20 MiB | 0 | 3 |

The CPU time-unit calibration ratio was 1.0000. Resident pages increased in the last interval while footprint decreased slightly; this bounded observation does not demonstrate a leak or sustained load. It is evidence from the existing installed pre-Sparkle artifact, not an energy measurement of the newly packaged update build. It does not establish battery life, sustained sync-load cost, an actual hourly callback, sleep/wake recovery, OS login registration or complete visual layout. No credentials, course/file names, document contents or raw traces are committed.

Hosted Intel execution is now established: PR #27's native job on `c102556` passed in 7m03s, including all 51 native tests, valid/invalid/interrupted updater fixtures, arm64 packaging and malformed-bundle rejection. Swift CodeQL passed in 10m47s. Later accepted head `17d3e0e` passed both required jobs and both reviewers before the confirmed squash merge in PR #27. Individual timings remain observations rather than a controlled architecture comparison.

## Faster CI baseline (November 11)

PR run 42922527155 (`macos-15-intel`, review-first CI) took about 16 minutes wall clock after both reviews: Change scope 8s; native 10m30s (`swift test` 3m59s, `test_updates.sh` 51s, release `package_release.sh` 5m09s); CodeQL 15m40s (traced `swift build` 11m40s, analyze 3m). The master push after merge took another 21 minutes. Branch `claude/faster-ci` runs CI in parallel with review, moves the native job to Apple Silicon with a non-traced `.build` cache and a debug PR bundle, and moves CodeQL off PRs. The first PR run on that branch, [42930899958](https://github.com/gnagster/StudSync/actions/runs/42930899958) (`macos-15`, cold `.build` cache, debug bundle, no CodeQL), started at push rather than after review and took 1m52s wall clock: classification 5s, native job 1m45s (`swift test` 1m01s, `test_updates.sh` 15s, debug `package_release.sh` 6s, cache save 6s). The local pre-push `swift test` (75 tests) plus push took 44s on an M1 Pro. This is one observation on a different runner architecture, not a controlled comparison; warm-cache, master and release timings remain to be recorded.
