# Changelog

All notable changes to PostedSDK iOS are documented here.

## [Unreleased — 3.0.0]

### Added

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
