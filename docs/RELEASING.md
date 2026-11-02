# Developer release procedure

The tag workflow creates a draft release containing an ad-hoc-signed Apple Silicon `.app` for macOS 15+, a ZIP archive and its SHA-256 checksum. A local maintainer signs the update archive before publication. Conventional GitHub tools and the local macOS Keychain suffice; no paid Apple identity, notarization service, or OpenAI API credentials are required.

After the release PR has merged and the desired commit has completed its required checks/review on `master`, create a new `vMAJOR.MINOR.PATCH` tag on that commit and push it. Do not tag an unreviewed development branch. The workflow rejects malformed versions and commits outside `master` history, runs native tests, packages the app, then creates a draft with generated change notes and `RELEASE_NOTES.md`. It fails on an existing release instead of replacing published assets. Build numbers use the release workflow run number; reruns keep that number. Versions and build numbers must increase for subsequent updates.

On the owner's Mac, after confirming the draft assets and tagged commit, run:

```sh
./script/publish_release.sh v0.1.0
```

The script requires a draft, downloads only its expected ZIP/checksum, verifies the checksum, generates an appcast using the pinned SDK and the project key directly in Keychain, and verifies its Ed25519 signature, byte length and exact GitHub asset URL against `config/Updates.plist`. Only then does it upload the appcast and publish as latest. The public feed is `https://github.com/gnagster/StudSync/releases/latest/download/appcast.xml`. A failed signature/key access leaves the draft unpublished. Inspect a partially completed draft before retrying; do not overwrite published assets.

The production key was created under Keychain account `com.gnagster.StudSync.updates`; only its public key is in `config/Updates.plist`. macOS may request access for Sparkle's `generate_appcast`. Do not export the private key, copy it into repository files, or upload it to CI. Losing that Keychain key prevents signing updates trusted by existing installations; provision a secure owner-managed recovery strategy before broader distribution. Fixture tests use a separate disposable key. The current local production-key signing attempt was stopped while waiting for macOS authorization; it has not yet produced a verified production appcast.

For local verification on Apple Silicon, choose an unused output directory:

```sh
./script/package_release.sh 0.1.0 1 /private/tmp/studsync-release-check
```

The packager uses a fresh temporary bundle, checks the extracted ZIP's signature, executable architecture, icon, localizations, bundled project/dependency licenses, identity, versions and minimum OS, and verifies its checksum. It does not install, launch, stop the running app or access credentials. Existing output archives are not overwritten. `build_and_run.sh` retains local installation at `~/Applications/StudSync.app`; both paths share `build_app.sh`.

PR CI also packages and validates the archive under the existing native check. `script/test_updates.sh` verifies an actual valid upgrade/relaunch, invalid-signature rejection and interrupted-download rejection with isolated native fixtures. No tag or public release is created by PR CI. Before the first actual tag, integrate outstanding fixes, inspect required CI/current-head review and complete production signing authorization. A valid local signature does not establish Gatekeeper trust, notarization or clean-machine launch. The first hosted publication, actual GitHub download and production-feed upgrade still require distribution verification. See `RELEASE_NOTES.md` for installation and update steps.
