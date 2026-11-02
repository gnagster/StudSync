# Developer release procedure

The tag workflow publishes an ad-hoc-signed Apple Silicon `.app` for macOS 15+, a ZIP archive and its SHA-256 checksum. It uses conventional GitHub tools; no paid Apple identity, notarization service, or OpenAI API credentials are required.

After the release PR has merged and the desired commit has completed its required checks/review on `master`, create a new `vMAJOR.MINOR.PATCH` tag on that commit and push it. Do not tag an unreviewed development branch. The workflow rejects malformed versions and commits outside `master` history, runs native tests, packages the app, then publishes a GitHub Release with generated change notes and the installation text in `RELEASE_NOTES.md`. It fails on an existing release instead of replacing published assets. Build numbers use the release workflow run number; reruns keep that number.

For local verification on Apple Silicon, choose an unused output directory:

```sh
./script/package_release.sh 0.1.0 1 /private/tmp/studsync-release-check
```

The packager uses a fresh temporary bundle, checks the extracted ZIP's signature, executable architecture, icon, localizations, bundled project/dependency licenses, identity, versions and minimum OS, and verifies its checksum. It does not install, launch, stop the running app or access credentials. Existing output archives are not overwritten. `build_and_run.sh` retains local installation at `~/Applications/StudSync.app`; both paths share `build_app.sh`.

PR CI also packages and validates the archive under the existing native check. No tag or public release is created by PR CI. Before the first actual tag, integrate outstanding correctness fixes, inspect required CI and current-head review, and keep the roadmap's remaining verification honest. A valid local signature does not establish Gatekeeper trust, notarization, clean-machine launch, authenticated sync or successful upgrades. Those require separate distribution/runtime checks. See `RELEASE_NOTES.md` for the user installation and manual-update steps; Sparkle remains future work.
