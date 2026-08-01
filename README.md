<img src="https://github.com/user-attachments/assets/c965b51b-7307-477a-8d22-9c9cd6da6231" alt="PostedSDK iOS SDK by Software Mansion" width="100%"/>

[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-ios-detour-1?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-ios-detour-1&n=1)
[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-ios-detour-2?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-ios-detour-2&n=1)
[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-ios-detour-3?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-ios-detour-3&n=1)

# PostedSDK iOS

PostedSDK is an iOS SDK for handling deferred deep links. A deferred link works like a regular deep link, but survives the App Store install — a user who clicks a link before having the app installed is redirected to the right screen on first launch. PostedSDK also handles Universal Links and custom scheme links in a single unified API.

## Quick links

- Documentation: [https://postedapp.com/docs/](https://postedapp.com/docs/) <!-- TODO(B6): update when new docs URL is live -->
- Installation guide: [https://postedapp.com/docs/sdk/ios/sdk-installation](https://postedapp.com/docs/sdk/ios/sdk-installation) <!-- TODO(B6): update when new docs URL is live -->

## Create an account

You need a Posted account to generate app credentials and configure your links.  
Sign up here: [https://postedapp.com](https://postedapp.com) <!-- TODO(B3): update once backend/site domain confirmed -->

## Installation

Latest stable release: `3.0.0`

### Requirements

- iOS 13.0+
- Swift 5.5+

### Swift Package Manager

In Xcode, go to `File > Add Package Dependencies...`, enter the repository URL, and add `PostedSDK` to your app target.

Or in `Package.swift`:

```swift
// TODO(B7): repo URL finalizes when the GitHub org/repo rename (board-gated) lands.
.package(url: "https://github.com/thepostedapp/posted-sdk-ios", from: "3.0.0")
```

### CocoaPods

In your `Podfile`:

```ruby
platform :ios, '13.0'

target 'YourAppTarget' do
  use_frameworks!
  pod 'PostedSDK', '3.0.0'
end
```

Then run `pod install`.

## Usage

### 1. Configure

```swift
import PostedSDK

let config = PostedConfig(
    apiKey: "<YOUR_POSTED_API_KEY>",
    appID: "<YOUR_POSTED_APP_ID>"
)
```

### 2. Resolve app launch (3.0.0+)

Call `resolveAppLaunch` once on cold start. Pass the `LaunchContext` from your delegate so the SDK
picks the correct attribution branch (link-present or deferred). Analytics are mounted automatically.

**Fire-once:** `resolveAppLaunch` records the attribution result on the first call and returns the
cached value on every subsequent call within the same install. Call `resetSession()` to re-arm
(testing only — do not call in production).

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

**Deferred-only (no URL context):** omit `launchContext` for installs with no incoming URL:

```swift
let result = await Posted.shared.resolveAppLaunch(config: config)
```

### 3. Handle runtime links

For links that arrive while the app is already running, read the URL directly from the delegate
callback and navigate — no SDK call is needed for runtime links:

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
    apiKey: "<YOUR_POSTED_API_KEY>",
    appID: "<YOUR_POSTED_APP_ID>",
    linkProcessingMode: .webOnly
)
```

</details>

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

See the [analytics docs](https://postedapp.com/docs/) <!-- TODO(B6): update when new docs URL is live --> for the full event list and retention tracking setup.

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

## Example project

A ready-to-run example covering deferred links, Universal Links, and custom scheme links is included at [`ExampleUsage/PostedExampleAppProject`](./ExampleUsage/PostedExampleAppProject). See the [example setup guide](./ExampleUsage/README.md) for instructions.

## Other platform SDKs

PostedSDK is also available for other app stacks:

<!-- TODO(B7): GitHub org/repo names finalize when the board-gated rename lands. -->

- Android SDK: [https://github.com/thepostedapp/posted-sdk-android](https://github.com/thepostedapp/posted-sdk-android)
- Flutter SDK: [https://github.com/thepostedapp/posted-sdk-flutter](https://github.com/thepostedapp/posted-sdk-flutter)
- React Native SDK: [https://github.com/thepostedapp/posted-sdk-react-native](https://github.com/thepostedapp/posted-sdk-react-native)

---

## Migrating from 2.x

### `resolveInitialLink` → `resolveAppLaunch`

`resolveInitialLink` is deprecated in 3.0.0 and will be removed in the next major release (4.0).
Replace it with `resolveAppLaunch(config:launchContext:)`:

| 2.x (deprecated) | 3.0.0+ |
|---|---|
| `resolveInitialLink(config:launchOptions:completion:)` | `resolveAppLaunch(config:launchContext: .launchOptions(launchOptions))` |
| `resolveInitialLink(config:connectionOptions:completion:)` | `resolveAppLaunch(config:launchContext: .connectionOptions(connectionOptions))` |

The new method is `async`/`await` — wrap the call in a `Task {}` from your delegate method.

### `processLink` → handle URLs directly

`processLink` is deprecated in 3.0.0. For cold-start attribution use `resolveAppLaunch`.
For runtime deep links (links that open an already-running app), read the URL from the system
delegate callback and navigate — no SDK call is required.

### Removal timeline

Deprecated methods (`resolveInitialLink`, `processLink`) will be removed in 4.0 (next major
release). Update before upgrading past 3.x to avoid breaking changes.

---

## License

This library is licensed under [The MIT License](./LICENSE).

## PostedSDK iOS is created by Software Mansion

Since 2012, [Software Mansion](https://swmansion.com) is a software agency with experience in building web and mobile apps. We are Core React Native Contributors and experts in dealing with all kinds of React Native issues. We can help you build your next dream product – [Hire us](https://swmansion.com/contact/projects?utm_source=detour&utm_medium=readme).

[![swm](https://logo.swmansion.com/logo?color=white&variant=desktop&width=150&tag=ios-detour-github "Software Mansion")](https://swmansion.com)
