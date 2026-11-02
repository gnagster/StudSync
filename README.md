# StudSync

<img src="Sources/StudSyncApp/Resources/ClassicFold.png" alt="StudSync Classic Fold logo" width="128">

A native macOS menu-bar app that brings Universität Göttingen Stud.IP course files into ordinary Finder folders. Personal Apple Silicon use comes first; macOS 15 or later is required.

## Build and run

Install Xcode and select its developer directory, then:

```sh
./script/build_and_run.sh
```

The script resolves the pinned Swift package, builds a release app, installs it at `~/Applications/StudSync.app`, signs and verifies it locally, and launches it. This stable location avoids file-provider metadata interfering with signatures in synced Documents folders and supports Start at Login. Codex's Run action uses the same command. `--build` builds/installs without launching; `--verify` launches it and verifies the process. `--logs`, `--telemetry`, and `--debug` support local diagnostics. Open `Package.swift` in Xcode for native editing/debugging.

This personal build is ad-hoc signed and not notarized. Keep the app at its installed location after enabling Start at Login.

## Download and install

Tagged builds are published on [GitHub Releases](https://github.com/gnagster/StudSync/releases) once a release tag is created. Download the `StudSync-…-arm64.zip` asset, unzip it, and move `StudSync.app` into your Applications folder. These builds require Apple Silicon and macOS 15+. Source-code archives are not compiled apps.

The app is ad-hoc signed and not notarized. If macOS blocks the first launch, try opening the app, then use System Settings → Privacy & Security → Open Anyway for StudSync and confirm. Only approve a download you trust; do not disable Gatekeeper globally. See the [installation and update notes](docs/RELEASE_NOTES.md). Sparkle 2 provides Check for Updates in the menu panel and opt-in automatic checks/downloads in Settings. Updates require the project's Ed25519 archive signature before extraction; no paid Apple identity is required. Developers use the [release procedure](docs/RELEASING.md).

## First launch

The first-run guide walks through university sign-in, Finder folder choice, course selection, and a final summary before starting sync. Use your university username without the email suffix. Back/Continue actions validate each step; progress, cancellation, and errors stay visible. Credentials are saved in macOS Keychain. Keychain access runs in the background so its authorization prompts cannot block the app from starting; macOS may still require your permission to read saved credentials. Cancelling immediately releases the app's login controls and discards late results, but cannot dismiss an authorization request already running inside macOS. Web login remains available; a new password save waits for the earlier Keychain request to return. The university web login is available for interactive/SSO sign-in; imported web sessions remain valid only as long as the university permits them. Settings and sync history live under `~/Library/Application Support/StudSync/`.

Existing files without a known baseline are preserved unless their content matches the server.

StudSync runs in the menu bar after its window closes. It defaults to hourly sync and offers manual, 15-minute, and four-hour intervals. It does not keep your Mac awake. Closing the panel does not quit the app; Quit does. Course files from selected current and previous semesters are supported.

Untouched files are updated atomically without retaining old copies. Locally edited files remain intact, with incoming server versions saved beside them. Remote deletion never deletes your local files. Use the menu-bar panel to see changes and reveal files in Finder.

Files and folders use readable names such as `Course/Notes/lecture.pdf`. Stud.IP identities and assigned names are tracked privately in the sync manifest. Collisions caused by duplicate titles, case differences, Unicode normalization, or replaced separators get a short numeric addition such as `lecture (2).pdf`. Assignments survive restarts and resources leaving a course, so a different file cannot inherit another file's baseline. Extensions are retained and excessively long stems are shortened.

On upgrade, previously tracked ID-named files move to their readable paths when those destinations are free, retaining local edits and existing baselines. Only empty old folders are removed. Unknown files, occupied destinations, and older incoming conflict copies are preserved; those older paths may remain. Existing files without proven ownership are never renamed automatically. Keep the current app version after this manifest upgrade; older builds cannot read the new manifest format.

If startup or sync fails offline, configured automatic sync retries when the network returns and at the selected interval. Paused/manual sync does not retry automatically, and rejected credentials require your attention. Each sync refreshes enrollment across all semesters. In setup/settings, browse the current semester, a previous semester, or All semesters; selections from other semesters remain active. Refreshing, reconnecting, and restarting keep selected course IDs. Select shown/Clear shown affect only the displayed semester. If none of your selected courses remain available, choose courses again rather than receiving a false “Up to date” result.

## Verification

```sh
./script/verify.sh
```

Verification runs shell workflow-helper regressions, native Swift tests, real Sparkle installation/rejection/interruption fixtures, a release app build and whitespace validation. Update fixtures launch their own disposable background app and localhost server with an ephemeral test key; they do not touch your StudSync installation or production signing key. CI runs native tests/app bundling plus Swift CodeQL. Fixtures do not require university credentials. Install Xcode and select its developer directory; there is no separate dependency environment to prepare.

The shared CI workflow classifies changes on Linux. Markdown-only PRs and master pushes (README, AGENTS, SECURITY and docs) skip both macOS jobs; GitHub's conditional-job skips satisfy their existing required contexts. There is no macOS build or CodeQL extraction for these changes. Classification failure fails the required jobs closed. Native/build changes, unknown inputs, empty diffs and code renames run full checks; the existing weekly CodeQL scan remains. CI uses Intel macOS runners after repeated ARM runner-capacity failures. Tests execute for the host; release packaging and traced app builds explicitly target arm64, and packages are rejected if their architecture differs. Local Apple Silicon tests cover the supported app architecture. The first Intel CodeQL job passed in 15m57s with all nine sources; a speedup over earlier runs is not established. Compiled build objects are never restored into the traced build; source caching has no established end-to-end improvement.

The optional `STUDSYNC_LIVE_TEST=1 swift test --filter liveGoettingenReadOnlyCheck` reads the native app's Keychain entry, signs into Göttingen, and verifies current/past enrollment and a small temporary course-file download. Sign in through the app first and grant macOS Keychain access when asked. The live check never runs in CI, never prints credentials, and does not change the sync destination or university files. It may wait for OS authorization; the default suite does not read real credentials.


## Development

See [AGENTS.md](AGENTS.md), [security policy](SECURITY.md), [roadmap](docs/ROADMAP.md), and [automation notes](docs/AUTOMATION.md). Development uses the owner's ChatGPT subscription; no OpenAI API credentials or API-billed Codex Actions are used. Automatic code review is configured in Codex repository settings, not by workflow YAML.
