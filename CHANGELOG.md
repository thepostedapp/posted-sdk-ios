# Changelog

All notable changes to `PostedSDK` iOS are documented here.

## [1.0.2]

### Added

- The install report includes `installSource`: `store` for an App Store or
  Google Play install, `development` for debug, TestFlight, ad hoc, emulator and
  Expo Go builds. It's read by a small native module bundled with the SDK, so
  update and rebuild the native app; no new dependencies. If the module isn't
  linked (e.g. new JS over the air on an older binary), the field is omitted.

## [1.0.1] — Initial public release

Initial public release of `PostedSDK` for iOS.

### Public API

- **`Posted.shared.reportInstall(config:)`** — reports the install once per
  install, so the backend can match it to the ad click and report the
  conversion. Call it on every launch: it retries on later launches until the
  backend accepts it, never throws, and never reads the clipboard.
- **`PostedConfig(apiKey:appID:)`** — the only configuration.
- **Backend API base**: `attr.postedapp.com`.
- Works with Swift Package Manager and CocoaPods on iOS 13.0+. Device data
  comes from `UIDevice`, `UIScreen`, `Locale` and `TimeZone`, with the user
  agent read from a `WKWebView`.
