# StudSync developer roadmap

Developer queue only. Follow `AGENTS.md` for ownership reconciliation, review/CI, security and releases. Use fresh master plus open PRs and actual code before selecting work; unmerged implementations reserve their scope.

## Active work

| Task | State / ownership | Remaining work and evidence |
| --- | --- | --- |
| Review-first GitHub CI and concise agent guidance | **In progress**, [PR #33](https://github.com/gnagster/StudSync/pull/33) | Codex completes a clean current-head review and CodeRabbit approves the same head before hosted tests/build/CodeQL; no local checks. Change scope is now a required GitHub Actions check; existing protections remain. Regression fixtures cover missing/stale/malformed Codex summaries, unresolved findings, rejected reviews, pagination and changed heads/base. Early run 41898361116 blocked macOS jobs before approval. CodeRabbit skill usage is documented; duplicate instructions/history are condensed. Next: clean current-head review and hosted CI, merge and confirm required-check association. Local checks intentionally not run. |
| Hosted dependency updates | **Planned** verification; fix **Merged**, [PR #27](https://github.com/gnagster/StudSync/pull/27) | Lowercase test-target paths fix Dependabot's Linux resolution error. Confirm the next hosted Swift update job after that fix; earlier native resolution/tests passed and no open alerts were reported at the last audit. |
| Controlled OS/runtime QA | **Planned**, needs a suitable test environment | Verify sleep/wake, Start at Login registration, sustained sync/battery behavior, complete on-screen layout and installation/relaunch through the production update feed. Existing observations show low process load and successful later sync, but do not establish these cases. Published v0.1.0/v0.1.1 provide upgrade targets. Synthetic/offscreen tests do not replace OS-level evidence. Do not interrupt/restart the owner's signed-in app, change its interval or disturb the Mac solely for QA. These are developer checks, not end-user acceptance tasks. |

## Merged features

| Scope | Implementation / evidence |
| --- | --- |
| Native app and tooling | Swift/SwiftUI menu-bar app; no external runtime. Native cleanup and fresh-checkout build/test/package verification: [PR #25](https://github.com/gnagster/StudSync/pull/25). |
| Authentication and recovery | Stud.IP API, Keychain, university web login, session reuse and one re-login after expiry. Responsive startup and stale-result cancellation: PR #21. An in-flight macOS authorization request cannot itself be cancelled. |
| Finder sync | Atomic updates, safe paths/symlinks, persistent readable names/collision assignments, manifest migration and preservation of local edits/unknown files: PR #18, closing #14. Older versions cannot read its upgraded manifest. |
| Setup and course selection | Four-step onboarding and current/past/all-semester selection with persistent enrollment: PR #20. Settings/network recovery and observable Start at Login feedback: PR #17, closing #15/#16. |
| Branding and status panel | Logo resources, adaptive monochrome S/red actionable errors, panel anchoring, independent error recovery, private settings backups and cancellation-safe web login: [PR #30](https://github.com/gnagster/StudSync/pull/30). Update checks remain in Settings. |
| Releases and Sparkle 2 | Arm64 downloads: PR #24. Authenticated updates, guarded owner-local Keychain signing/publication, interrupted-sync and real updater/rejection fixtures: [PR #27](https://github.com/gnagster/StudSync/pull/27), preserving/superseding PR #23. Procedure: [RELEASING.md](RELEASING.md). |
| CI and developer coordination | Documentation-only skips, native checks, full Swift CodeQL coverage and ownership reconciliation: PR #27, preserving PR #26. Intel CI builds arm64 releases; no compiled objects restored for traced builds. Cache measurements: [PERFORMANCE.md](PERFORMANCE.md). PR #33 changes review sequencing; it is not merged yet. |

## Published versions and verification

- [v0.1.0](https://github.com/gnagster/StudSync/releases/tag/v0.1.0): PR #27 at `caccb5f`; master CI 41490637107 and release build 41492981802 passed. Anonymous archive/checksum/feed, Ed25519 signature, app identity/architecture/version and deep codesign verification passed.
- [v0.1.1](https://github.com/gnagster/StudSync/releases/tag/v0.1.1): PR #30 at `075a8fb`, build 2. PR CI 41558280523, master CI 41561737803 and release build 41563694026 passed. Verification covered 64 native tests, all 11 Swift sources, updater/malformed-bundle fixtures and public archive/checksum/signed-feed identity checks including logo resources. Signing/publication is complete; the private key stayed in Keychain.

Historical review/test details remain in the linked PRs and Git history. Neither release's publication nor synthetic updater tests establish the production-feed installation or complete UI/OS QA listed above. Developer ID/notarization, wider hardware support and broader distribution testing remain later scope.
