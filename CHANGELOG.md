# Changelog

All notable changes to PostedSDK iOS are documented here.

## [4.0.1] — Install reporting

- **Install reporting** — `resolveAppLaunch` now reports the install to `POST /api/install`
  (fingerprint + device id), so installs from Posted `sdk` campaigns are counted and reported to
  TikTok/Meta as conversions. Sent once per install; retried on later launches until the backend
  accepts it, including launches that return a cached fire-once result. Never reads the
  clipboard. Parity with the React Native SDK.
- **`Posted.shared.reportInstall(config:)`** — reports the install without `resolveAppLaunch`, for
  apps that resolve deep links themselves. Safe to call on every launch; never throws.

## [4.0.0] — Initial public release

- CPI tracking and deep-link attribution for native iOS apps.
- **`resolveAppLaunch(config:launchContext:)`** — unified cold-start attribution method. Pass a
  `LaunchContext` value from your app or scene delegate; omit it for deferred-only (no incoming
  URL) scenarios.
- **`LaunchContext`** enum — wraps the two delegate entry points:
  - `.launchOptions([UIApplication.LaunchOptionsKey: Any]?)` — from `AppDelegate`
  - `.connectionOptions(UIScene.ConnectionOptions)` — from `SceneDelegate`
- **Fire-once semantics** — `resolveAppLaunch` records the attribution result after the first
  successful call and returns the cached value on all subsequent calls within the same install.
  Cache is keyed by a versioned schema; a version mismatch transparently re-resolves rather than
  crashing. Call `resetSession()` to re-arm (testing only).
- **`PostedResult.resolutionFailed`** — public read-only `Bool` distinguishing a genuine
  network/transport failure from a legitimate "asked the server, no match" response (both
  otherwise surface identically as `processed: true, link: nil`). Read it only from a fresh
  `resolveAppLaunch` completion result; a reloaded/cached result always reports `false`.
- **`posted://` custom URL scheme** registered in the example app's `Info.plist`
  (`CFBundleURLTypes`), demonstrating custom-scheme deep links alongside the clipboard-token
  deferred flow.
