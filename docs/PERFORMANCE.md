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
