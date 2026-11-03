# Developer release procedure

The tag workflow creates a draft release containing an ad-hoc-signed Apple Silicon `.app` for macOS 15+, a ZIP archive and its SHA-256 checksum. A local maintainer signs the update archive before publication. Conventional GitHub tools and the local macOS Keychain suffice; no paid Apple identity, notarization service, or OpenAI API credentials are required.

After the release PR has merged and the desired commit has completed its required checks/review on `master`, create a new `vMAJOR.MINOR.PATCH` tag on that commit and push it. Do not tag an unreviewed development branch. The workflow rejects malformed versions and commits outside `master` history, runs native tests, packages the app, then creates a draft with generated change notes and `RELEASE_NOTES.md`. It fails on an existing release instead of replacing published assets. Build numbers use the release workflow run number; reruns keep that number. Versions and build numbers must increase for subsequent updates.

On the owner's Mac, after confirming the draft assets and tagged commit, run:

```sh
./script/publish_release.sh v0.1.0
```

The script requires a draft, downloads only its expected ZIP/checksum, verifies the checksum, generates an appcast using the pinned SDK and the project key directly in Keychain, and verifies its Ed25519 signature, byte length and exact GitHub asset URL against `config/Updates.plist`. Only then does it upload the appcast and publish as latest. The public feed is `https://github.com/gnagster/StudSync/releases/latest/download/appcast.xml`. A failed signature/key access leaves the draft unpublished. Inspect a partially completed draft before retrying; do not overwrite published assets.

The production key was created under Keychain account `com.gnagster.StudSync.updates`; only its public key is in `config/Updates.plist`. macOS may request access for Sparkle's `generate_appcast`, including on a later invocation after an earlier allowance. Do not export the private key, copy it into repository files, or upload it to CI. Losing that Keychain key prevents signing updates trusted by existing installations; provision a secure owner-managed recovery strategy before broader distribution. Fixture tests use a separate disposable key. The production key has been exercised locally against the public trust anchor: signature, byte-length and exact-URL verification passed. Current hosted publication status belongs to `ROADMAP.md` and GitHub Releases.

If the signer reports Keychain error `-25320` (`errSecInDarkWake`), wake and unlock the owner's Mac before retrying the existing draft. This code means authorization UI is unavailable during dark wake; it does not establish that the key is missing. Do not regenerate the production key in response to that error. The failed publisher leaves the draft unpublished.

For local verification on macOS with Xcode, choose an unused output directory. Packaging explicitly builds arm64 even on an Intel host; the resulting app still requires Apple Silicon:

```sh
./script/package_release.sh 0.1.0 1 /private/tmp/studsync-release-check
```

The packager uses a fresh temporary bundle, checks the extracted ZIP's signature, executable architecture, icon, localizations, bundled project/dependency licenses, identity, versions and minimum OS, and verifies its checksum. It does not install, launch, stop the running app or access credentials. Existing output archives are not overwritten. `build_and_run.sh` retains local installation at `~/Applications/StudSync.app`; both paths share `build_app.sh`.

PR CI also packages and validates the archive under the existing native check. `script/test_updates.sh` verifies an actual valid upgrade/relaunch, invalid-signature rejection and interrupted-download rejection with isolated native fixtures. `script/test_release_helpers.sh` verifies that corrupt assets, unsafe checksum filenames, signing errors and upload errors cannot publish a release, using isolated command fixtures without real credentials or signing keys. `script/test_release_bundle.sh` accepts a verified ZIP, then tests a valid control and re-signed copies with invalid version, identity and update-verification settings; every malformed bundle must be rejected before output publication. Package and fixture assertions explicitly fail on macOS Bash 3.2 instead of relying on `set -e` for compound conditions. No tag or public release is created by PR CI. Before each tag, integrate outstanding fixes and inspect required CI/current-head review. A valid local signature does not establish Gatekeeper trust, notarization, clean-machine launch or a production-feed upgrade. Verify each actual publication and public download separately; completed publication evidence belongs in `ROADMAP.md`. See `RELEASE_NOTES.md` for installation and update steps.
