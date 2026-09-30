# PostedSDK iOS

PostedSDK is an iOS SDK for handling deferred deep links. A deferred link works like a regular deep link, but survives the App Store install — a user who clicks a link before having the app installed is redirected to the right screen on first launch. PostedSDK also handles Universal Links and custom scheme links in a single unified API.

## Quick links

- **Getting-Started guide** (cross-platform golden path — create an app, install, verify): [GETTING-STARTED.md](https://github.com/thepostedapp/posted-sdk-admin/blob/main/GETTING-STARTED.md). This README is the full iOS reference.
- **API host**: `attr.postedapp.com` (the SDK targets this by default — you do not configure it). Deep links resolve via `l.postedapp.com`.
- **Troubleshooting**: [TROUBLESHOOTING.md](https://github.com/thepostedapp/posted-sdk-admin/blob/main/TROUBLESHOOTING.md)
- **Backend contract redoc**: not yet live <!-- TODO(POS-589): link once the contract redoc is hosted — Firebase Hosting activation is gated on the POS-312 D1/D2 DNS decision -->
- **Support**: see [Support](#support) below

## Create account

You need a Posted account to generate app credentials (`app_id` + API key) and configure your links. Follow [**Create an app & find your credentials**](https://github.com/thepostedapp/posted-sdk-admin/blob/main/README.md#create-an-app--find-your-credentials) in the dashboard README — it covers the full create-app flow and where each credential appears afterward.

## Install

Latest stable release: `4.0.0`

### Requirements

- iOS 13.0+
- Swift 5.5+

### Swift Package Manager

In Xcode, go to `File > Add Package Dependencies...`, enter the repository URL, and add `PostedSDK` to your app target.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/thepostedapp/posted-sdk-ios", from: "4.0.0")
```

### CocoaPods

In your `Podfile`:

```ruby
platform :ios, '13.0'

target 'YourAppTarget' do
  use_frameworks!
  pod 'PostedSDK', '4.0.0'
end
```

Then run `pod install`.

## Quickstart

The fastest way to get attribution working: build a `PostedConfig` and call `resolveAppLaunch` once on cold start, passing the `LaunchContext` from your app or scene delegate.

```swift
import PostedSDK

let config = PostedConfig(
    apiKey: "<YOUR_API_KEY>",
    appID: "<YOUR_APP_ID>"
)

// In application(_:didFinishLaunchingWithOptions:) or scene(_:willConnectTo:options:):
Task {
    let result = await Posted.shared.resolveAppLaunch(
        config: config,
        launchContext: .launchOptions(launchOptions)
    )
    if let link = result.link {
        // Navigate to link.route
    }
}
```

See [Deep-link handling](#deep-link-handling) below for full app delegate / scene delegate examples, and [resolveAppLaunch](#resolveapplaunch) for fire-once semantics.

## Configure

Beyond `apiKey` and `appID`, `PostedConfig` accepts one optional knob:

- **`shouldUseClipboard`** — iOS clipboard check for deferred-link matching, defaults to `true`.
- **`linkProcessingMode`** — controls which link sources the SDK handles (`.all` | `.webOnly` | `.deferredOnly`, default `.all`). See [Deep-link handling](#controlling-which-links-postedsdk-processes) for the full behavior table.

See [Types → PostedConfig](#postedconfig) for the full type definition.

## resolveAppLaunch

```swift
func resolveAppLaunch(config: PostedConfig, launchContext: LaunchContext? = nil) async -> PostedResult
```

The single unified cold-start attribution entry point. Pass the `LaunchContext` from your delegate so the SDK picks the correct attribution branch (link-present or deferred). Analytics are mounted automatically.

- **Fire-once per install**: the first call resolves and caches the result; every subsequent call within the same install returns the cached value instead of re-resolving.
- Omit `launchContext` for installs with no incoming URL (deferred-only scenarios):

```swift
let result = await Posted.shared.resolveAppLaunch(config: config)
```

### resetSession

```swift
func resetSession(allowDeferredRetry: Bool = false)
```

Re-arms the fire-once resolution so the next `resolveAppLaunch` call resolves fresh instead of returning the cached value. Testing only — do not call in production.

## Deep-link handling

For links that arrive while the app is already running, read the URL directly from the delegate callback and navigate — no SDK call is needed for runtime links.

**App delegate:**

<details>
<summary>AppDelegate example</summary>

```swift
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    Task {
        let result = await Posted.shared.resolveAppLaunch(
            config: config,
            launchContext: .launchOptions(launchOptions)
        )
        if let link = result.link {
            // Navigate to link.route
        }
    }
    return true
}
```

</details>

**Scene delegate:**

<details>
<summary>SceneDelegate example</summary>

```swift
func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
) {
    Task {
        let result = await Posted.shared.resolveAppLaunch(
            config: config,
            launchContext: .connectionOptions(connectionOptions)
        )
        if let link = result.link {
            // Navigate to link.route
        }
    }
}
```

</details>

**Runtime custom scheme link:**

<details>
<summary>Custom scheme (app delegate)</summary>

```swift
func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
) -> Bool {
    // Parse url.path / url.host and navigate as needed.
    return true
}
```

</details>

**Runtime Universal Link:**

<details>
<summary>Universal Link (app delegate)</summary>

```swift
func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else { return false }
    // Navigate to url.
    return true
}
```

</details>

### Controlling which links PostedSDK processes

Use `linkProcessingMode` to control which link sources the SDK handles:

| Value               | Universal links | Deferred links | Custom scheme links |
| ------------------- | --------------- | -------------- | ------------------- |
| `.all` (default)    | ✅              | ✅             | ✅                  |
| `.webOnly`          | ✅              | ✅             | ❌                  |
| `.deferredOnly`     | ❌              | ✅             | ❌                  |

<details>
<summary>linkProcessingMode config example</summary>

```swift
let config = PostedConfig(
    apiKey: "<YOUR_API_KEY>",
    appID: "<YOUR_APP_ID>",
    linkProcessingMode: .webOnly
)
```

</details>

### Continuous deep-link stream (cross-platform surface)

The **continuous deep-link stream** delivers every link the app receives while it is running (warm links). It is a **separate feature from fire-once install attribution**: `resolveAppLaunch` resolves the single deferred/deep link responsible for the install exactly once (cached thereafter), whereas the continuous stream is unrelated to attribution and emits on every warm link for the life of the process. Use `resolveAppLaunch` for attribution; use the native warm-link path above for ongoing in-session navigation.

The stream is an idiomatic convenience exposed **only on the JS/Dart wrappers**, which already sit on top of a framework-level URL event bus (React Native `Linking`, Flutter `EventChannel`). Native iOS/Android apps deliver warm links through platform lifecycle hooks instead — this divergence is **intentional, not a gap**.

| Platform | Continuous stream API | Status | Warm-link path |
|----------|----------------------|--------|----------------|
| Flutter (`PostedSdk`) | `Stream<PostedResult> get linkStream` | ✅ present, non-deprecated (EventChannel-backed) | via `linkStream` |
| React Native (`Posted`) | `addEventListener("url", listener) → PostedUrlSubscription` | ✅ present, non-deprecated (mirrors RN core `Linking`) | via `addEventListener` |
| Android (`Posted`) | — none (intentional) — | ➖ not offered | `PostedDelegate.onNewIntent(intent)` → `resolveAppLaunch()` |
| iOS (`Posted`) | — none (intentional) — | ➖ not offered | Scene/App URL handling (`scene(_:willConnectTo:)`, `openURL`, `continueUserActivity`) → `resolveAppLaunch()` |

**Fire-once vs continuous** — `resolveAppLaunch` fires once per install and returns the attribution result; the continuous stream never participates in attribution and fires on every warm link.

## Analytics

Analytics are mounted automatically when you call `resolveAppLaunch`. To log custom events use the predefined `PostedEventName` enum or a custom string:

<details>
<summary>Analytics example</summary>

```swift
PostedAnalytics.logEvent(.addToCart, data: ["sku": "abc"])
PostedAnalytics.logEvent("custom_event", data: ["source": "home"])
PostedAnalytics.logRetention("week_1")
```

</details>

If you need analytics without calling `resolveAppLaunch`, mount and unmount manually:

```swift
Posted.shared.mountAnalytics(config: config)
// ...
Posted.shared.unmountAnalytics()
```

See the analytics documentation for the full event list and retention tracking setup.

## Types

### PostedConfig

<details>
<summary>PostedConfig</summary>

```swift
public struct PostedConfig {
    public let apiKey: String
    public let appID: String
    public let shouldUseClipboard: Bool       // default: true
    public let linkProcessingMode: LinkProcessingMode  // default: .all
}
```

</details>

### PostedResult

<details>
<summary>PostedResult</summary>

```swift
public struct PostedResult {
    public let processed: Bool
    public let link: PostedLink?
    // True on a genuine network/transport failure, false otherwise (including a legitimate
    // "asked the server, no match" response). Only meaningful on a fresh completion result —
    // a reloaded/cached result always reports false.
    public let resolutionFailed: Bool

    // Convenience accessors
    public var route: String?
    public var linkType: LinkType?
    public var pathname: String?
    public var params: [String: String]
    public var linkURL: URL?
}
```

</details>

### PostedLink

<details>
<summary>PostedLink</summary>

```swift
public struct PostedLink {
    public let url: String
    public let route: String
    public let pathname: String
    public let params: [String: String]
    public let type: LinkType
}
```

</details>

### LinkType

<details>
<summary>LinkType</summary>

```swift
public enum LinkType: String {
    case deferred   // User clicked link before app was installed
    case verified   // Universal Link — http/https with verified domain ownership
    case scheme     // Custom scheme deep link (e.g. myapp://...)
}
```

</details>

### LinkProcessingMode

<details>
<summary>LinkProcessingMode</summary>

```swift
public enum LinkProcessingMode: String {
    case all
    case webOnly
    case deferredOnly
}
```

</details>

### LaunchContext

<details>
<summary>LaunchContext</summary>

```swift
public enum LaunchContext {
    case launchOptions([UIApplication.LaunchOptionsKey: Any]?)
    case connectionOptions(UIScene.ConnectionOptions)
}
```

</details>

## API Reference

Every public export, with a pointer to where it's documented in depth:

| Export | Kind | Docs |
|---|---|---|
| `Posted.shared.resolveAppLaunch(config:launchContext:)` | method | [resolveAppLaunch](#resolveapplaunch) |
| `Posted.shared.resetSession(allowDeferredRetry:)` | method | [resolveAppLaunch → resetSession](#resetsession) |
| `Posted.shared.mountAnalytics(config:)` / `Posted.shared.unmountAnalytics()` | method | [Analytics](#analytics) |
| `PostedAnalytics.logEvent` / `PostedAnalytics.logRetention` | method | [Analytics](#analytics) |
| `PostedEventName` | enum | [Analytics](#analytics) |
| `PostedConfig`, `PostedResult`, `PostedLink`, `LinkType`, `LinkProcessingMode`, `LaunchContext` | types | [Types](#types) |

The table above is hand-maintained. A full generated reference (every public symbol and doc
comment) is built with [DocC](https://github.com/apple/swift-docc-plugin) on every PR to `main` —
the `docs` CI job fails the build if generation breaks, so it can't silently drift from
`Sources/PostedSDK`. Hosting the generated output is tracked separately <!-- TODO(POS-590): link
once hosted -->; until then, build it locally:

```bash
xcodebuild docbuild -scheme PostedSDK -destination 'generic/platform=iOS' -derivedDataPath ./.docc-build
```

## Errors/Troubleshooting

See the canonical [Troubleshooting & error-code reference](https://github.com/thepostedapp/posted-sdk-admin/blob/main/TROUBLESHOOTING.md) — 401s, no-match, deferred deep links not firing, clipboard edge cases, and key rotation, each with cause → how to detect → fix.

## Migration

PostedSDK 3.0.0 is **attribution-first**: instead of juggling several link-handling calls, your
app calls one method — `resolveAppLaunch` — once per cold start and gets back the attribution
result for that install. This section covers what changed and how to adopt it.

### `resolveInitialLink` → `resolveAppLaunch`

`resolveInitialLink` was removed in **4.0.0**. Replace it with `resolveAppLaunch(config:launchContext:)`:

| 2.x (removed) | 3.0.0+ |
|---|---|
| `resolveInitialLink(config:launchOptions:completion:)` | `resolveAppLaunch(config:launchContext: .launchOptions(launchOptions))` |
| `resolveInitialLink(config:connectionOptions:completion:)` | `resolveAppLaunch(config:launchContext: .connectionOptions(connectionOptions))` |

The new method is `async`/`await` — wrap the call in a `Task {}` from your delegate method. Both
`resolveInitialLink` overloads' separate parameters are unified behind a single `LaunchContext`
enum (`.launchOptions(...)` / `.connectionOptions(...)`) — pass the value from your app or scene
delegate, as shown in [resolveAppLaunch](#resolveapplaunch).

### Fire-once semantics

`resolveAppLaunch` resolves attribution **once per install**: the first call resolves and caches
the result, and every subsequent call within the same install — including across app updates —
returns the cached value instead of re-resolving. The cache re-arms automatically on reinstall.
Call `resetSession()` to re-arm manually; this is for testing only — do not call it in production.

### `processLink` → handle URLs directly

`processLink` was removed in **4.0.0**. For cold-start attribution use `resolveAppLaunch`.
For runtime deep links (links that open an already-running app), read the URL from the system
delegate callback and navigate — no SDK call is required.

### Removal timeline

`resolveInitialLink` and `processLink` were deprecated in 3.0.0 and have been removed in **4.0.0**.
The public surface is now `mountAnalytics`/`unmountAnalytics`, `resolveAppLaunch`, and `resetSession`.
Apps still calling the removed methods must migrate before upgrading past 3.x.

## Versioning/compatibility

- **SDK version**: `4.0.0` (aligned across iOS/Android/React Native/Flutter)
- **Backend contract**: `1.1.0`, served from `attr.postedapp.com`
- **Min iOS**: `13.0+` · **Min Swift**: `5.5+` (see `s.ios.deployment_target` / `s.swift_version` in [`PostedSDK.podspec`](./PostedSDK.podspec), or `platforms` / `swift-tools-version` in [`Package.swift`](./Package.swift))
- **Cross-platform compatibility matrix**: [COMPATIBILITY.md](https://github.com/thepostedapp/posted-sdk-admin/blob/main/COMPATIBILITY.md)

## Example

A ready-to-run example covering deferred links, Universal Links, and custom scheme links is included at [`ExampleUsage/PostedExampleAppProject`](./ExampleUsage/PostedExampleAppProject). See the [example setup guide](./ExampleUsage/README.md) for instructions.

## Support

- Found a bug or have a question specific to this SDK? [Open an issue](https://github.com/thepostedapp/posted-sdk-ios/issues) on this repo.

### Other posted-sdk SDKs

posted-sdk is also available for other app stacks:

- Android SDK: [https://github.com/thepostedapp/posted-sdk-android](https://github.com/thepostedapp/posted-sdk-android)
- React Native SDK: [https://github.com/thepostedapp/posted-sdk-react-native](https://github.com/thepostedapp/posted-sdk-react-native)
- Flutter SDK: [https://github.com/thepostedapp/posted-sdk-flutter](https://github.com/thepostedapp/posted-sdk-flutter)
