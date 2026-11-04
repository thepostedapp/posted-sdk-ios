# Changelog

All notable changes to `PostedSDK` iOS are documented here.

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
