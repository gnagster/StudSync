# Contributing to StudSync

StudSync is a native Swift/SwiftUI menu-bar app. Networking and sync live in `StudSyncCore`, presentation in `StudSyncApp`. Personal Apple Silicon use comes first; macOS 15 or later is required. The user-facing documentation is [README.md](README.md) and [README.de.md](README.de.md).

## Build and run

Install Xcode and select its developer directory, then:

```sh
./script/build_and_run.sh
```

The script resolves the pinned Swift package, builds a release app, installs it at `~/Applications/StudSync.app`, signs and verifies it locally, and launches it. This stable location avoids file-provider metadata interfering with signatures in synced Documents folders and supports Start at Login. `--build` builds/installs without launching; `--verify` launches it and verifies the process. `--logs`, `--telemetry`, and `--debug` support local diagnostics. Open `Package.swift` in Xcode for native editing/debugging.

This personal build is ad-hoc signed and not notarized. Keep the app at its installed location after enabling Start at Login.

## Verification

Automated verification runs in GitHub Actions after review; contributors do not need to run the checks locally. `script/verify.sh` remains available as shared tooling:

```sh
./script/verify.sh
```

It runs shell workflow-helper regressions, native Swift tests, real Sparkle installation/rejection/interruption fixtures, a release app build and whitespace validation. Update fixtures launch their own disposable background app and localhost server with an ephemeral test key; they do not touch your StudSync installation or production signing key. CI runs native tests/app bundling plus Swift CodeQL. Fixtures do not require university credentials. There is no separate dependency environment to prepare.

PR checks run on GitHub after Codex has completed a clean review and CodeRabbit has reviewed and approved that same current commit, with all review threads resolved. Earlier review decisions fail the inexpensive required Change scope gate; expensive native/CodeQL jobs wait. New pushes need a fresh review. Master pushes and the weekly scan remain enabled. The shared CI workflow classifies changes on Linux. Markdown-only PRs and master pushes (README, CONTRIBUTING, AGENTS, SECURITY and docs) skip both macOS jobs; GitHub's conditional-job skips satisfy their existing required contexts. Classification/review failure fails the required Change scope check closed. Native/build changes, unknown inputs, empty diffs and code renames run full checks; the weekly CodeQL scan remains. CI uses Intel macOS runners after repeated ARM runner-capacity failures. Tests execute for the host; release packaging and traced app builds explicitly target arm64, and packages are rejected if their architecture differs.

The optional `STUDSYNC_LIVE_TEST=1 swift test --filter liveGoettingenReadOnlyCheck` reads the native app's Keychain entry, signs into Göttingen, and verifies current/past enrollment and a small temporary course-file download. Sign in through the app first and grant macOS Keychain access when asked. The live check never runs in CI, never prints credentials, and does not change the sync destination or university files.

## README screenshots

The screenshots in `docs/images` are rendered from sample data, never from a real account, in English and German:

```sh
STUDSYNC_SCREENSHOTS=docs/images swift test --filter ReadmeScreenshots
```

The windows appear on screen for a moment while they are captured. Regenerate the images when the panel, onboarding or settings change visibly.

## How sync behaves

These details matter when changing the sync engine:

- Untouched files are updated atomically without retaining old copies. Locally edited files remain intact, with incoming server versions saved beside them. Remote deletion never deletes local files. Existing files without a known baseline are preserved unless their content matches the server.
- Files and folders use readable names such as `Course/Notes/lecture.pdf`. Stud.IP identities and assigned names are tracked privately in the sync manifest. Collisions caused by duplicate titles, case differences, Unicode normalization or replaced separators get a short numeric addition such as `lecture (2).pdf`. Assignments survive restarts and resources leaving a course, so a different file cannot inherit another file's baseline. Extensions are retained and excessively long stems are shortened.
- On upgrade, previously tracked ID-named files move to their readable paths when those destinations are free, retaining local edits and baselines. Only empty old folders are removed. Unknown files, occupied destinations and older conflict copies are preserved. Older builds cannot read the new manifest format.
- If startup or sync fails offline, configured automatic sync retries when the network returns and at the selected interval. Paused/manual sync does not retry automatically, and rejected credentials require attention. Each sync refreshes enrollment across all semesters; selections from other semesters remain active. If none of the selected courses remain available, the user must choose again instead of seeing a false “Up to date”.
- Credentials are saved in the macOS Keychain. Keychain access runs in the background so authorization prompts cannot block startup. Cancelling releases the login controls and discards late results, but cannot dismiss an authorization request already running inside macOS. Imported web sessions remain valid only as long as the university permits them. Settings and sync history live under `~/Library/Application Support/StudSync/`.

## Releases

Sparkle 2 provides Check for Updates and opt-in automatic checks/downloads. Updates require the project's Ed25519 archive signature before extraction; no paid Apple identity is required. See the [release procedure](docs/RELEASING.md) and [installation and update notes](docs/RELEASE_NOTES.md).

## Project rules

Read [AGENTS.md](AGENTS.md), the [security policy](SECURITY.md), the [roadmap](docs/ROADMAP.md) and the [automation notes](docs/AUTOMATION.md) before larger changes. Keep the roadmap current in every PR. Development uses the owner's ChatGPT subscription; no OpenAI API credentials or API-billed Codex Actions are used. Keep both Codex and CodeRabbit PR reviews enabled; both must finish and findings must be handled before CI.
