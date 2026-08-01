# Changelog

All notable changes to PostedSDK iOS are documented here.

## [Unreleased — 3.0.0]

### Changed

- **Go-live rebrand (metadata).** Podspec `homepage`/`source`/`social_media_url` now point at the
  `posted-sdk-ios` GitHub repository and the author contact email is `yuriy@postedapp.com`.
  Documentation, account/sign-up, and cross-platform SDK links in the README now use posted URLs.
  Sample API-key placeholder value uses the `posted_` prefix.
  - The backend API domain (`godetour.dev`) and the short-link/Universal-Link example domain
    (`godetour.link`) are intentionally **unchanged** in this release; those cutovers are gated on
    DNS/backend readiness and land in lockstep across all platform SDKs (`TODO(B3)`/`TODO(B4)`).

### Added

- **`posted://` custom URL scheme** registered in the example app's `Info.plist`
  (`CFBundleURLTypes`), demonstrating custom-scheme deep links alongside the existing
  clipboard-token deferred flow.
- **`resolveAppLaunch(config:launchContext:)`** — new unified cold-start attribution method.
  Replaces both `resolveInitialLink` overloads. Pass a `LaunchContext` value from your app or
  scene delegate; omit it for deferred-only (no incoming URL) scenarios.
- **`LaunchContext`** enum — wraps the two delegate entry points:
  - `.launchOptions([UIApplication.LaunchOptionsKey: Any]?)` — from `AppDelegate`
  - `.connectionOptions(UIScene.ConnectionOptions)` — from `SceneDelegate`
- **Fire-once semantics** — `resolveAppLaunch` records the attribution result after the first
  successful call and returns the cached value on all subsequent calls within the same install.
  Cache is keyed by a versioned schema; a version mismatch transparently re-resolves rather than
  crashing. Call `resetSession()` to re-arm (testing only).
- **Defensive flag–cache consistency** — the fire-once resolved flag is only set after the
  result is successfully encoded to the cache; no silent divergence between flag and blob.
- **`PostedResult.resolutionFailed`** — public read-only `Bool` distinguishing a genuine
  network/transport failure from a legitimate "asked the server, no match" response (both
  previously surfaced identically as `processed: true, link: nil`). Matches the discriminator
  `android-detour`'s `LinkResult.Error` case already exposes, closing the cross-platform gap for
  consumers (e.g. the Flutter plugin) that must skip fire-once caching on failure. Kept out of the
  persisted fire-once cache envelope's JSON — read it only from a fresh `resolveAppLaunch` /
  `resolveInitialLink` completion result; a reloaded/cached result always reports `false`.

### Deprecated

- `resolveInitialLink(config:launchOptions:completion:)` — migrate to `resolveAppLaunch`.
- `resolveInitialLink(config:connectionOptions:completion:)` — migrate to `resolveAppLaunch`.
- `processLink(_:)`, `processLink(_:config:)` (all overloads) — for cold-start attribution use
  `resolveAppLaunch`; for runtime deep links handle the URL directly from your delegate callback.

### Migration guide

See [Migrating from 2.x](./README.md#migrating-from-2x) in the README.

Deprecated symbols will be **removed in 4.0** (next major release).

---

## [2.0.0]

- Rebrand: SDK renamed from `Detour` to `PostedSDK`. Package identifier changed to
  `PostedSDK`; the legacy `Detour` CocoaPod carries a deprecation notice.
- All public types renamed: `DetourConfig` → `PostedConfig`, `DetourResult` → `PostedResult`,
  `DetourLink` → `PostedLink`, `DetourAnalytics` → `PostedAnalytics`.
