# PostedSDK iOS

`PostedSDK` reports app installs to Posted. The backend matches each install to the ad click that led to it and reports it back to the ad network as a conversion.

The SDK has one function, `reportInstall(config:)`. Call it on every app launch. It sends the report once per install.

- [Requirements](#requirements)
- [Get your app ID and API key](#get-your-app-id-and-api-key)
- [1. Install](#1-install)
- [2. Report the install](#2-report-the-install)
- [3. Verify the integration](#3-verify-the-integration)
- [Configuration](#configuration)
- [Data collected](#data-collected)
- [Troubleshooting](#troubleshooting)
- [Support](#support)

## Requirements

- iOS 13.0+
- Swift 5.5+
- An app ID and API key from the Posted dashboard. See [Get your app ID and API key](#get-your-app-id-and-api-key).

## Get your app ID and API key

Both come from the Posted dashboard at [app.postedapp.com/dashboard/settings](https://app.postedapp.com/dashboard/settings), under **Posted SDK**.

1. Under **Apps**, click **Add app** and enter your app's details. The dashboard shows its **app ID** (`app_…`).
2. Under **API keys**, click **Create key**. Copy the key when it is shown; it is not displayed again.

Pass these as `appID` and `apiKey` in `PostedConfig`. One API key works for all apps in your account.

## 1. Install

### Swift Package Manager

In Xcode, go to `File > Add Package Dependencies...`, enter the repository URL, and add `PostedSDK` to your app target.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/thepostedapp/posted-sdk-ios", from: "1.0.0")
```

### CocoaPods

In your `Podfile`:

```ruby
platform :ios, '13.0'

target 'YourAppTarget' do
  use_frameworks!
  pod 'PostedSDK', '~> 1.0'
end
```

Then run `pod install`.

## 2. Report the install

Call `reportInstall(config:)` once per launch, as early as possible: in `application(_:didFinishLaunchingWithOptions:)`, or in your `App` initializer with SwiftUI.

```swift
import PostedSDK

let config = PostedConfig(
    apiKey: "<YOUR_API_KEY>",
    appID: "<YOUR_APP_ID>"
)

Task {
    await Posted.shared.reportInstall(config: config)
}
```

You don't need to wait for it. It never throws, and it doesn't block app startup.

## 3. Verify the integration

1. Run the app with a **fresh install**. Deleting the app clears the SDK's storage, so a reinstall reports again.
2. Watch the Console logs for the `com.postedapp.posted` subsystem. On success you'll see `Install reported`. On failure, a line starting with `[Posted:INSTALL_ERROR]` (see [Troubleshooting](#troubleshooting)).

## Configuration

```swift
Posted.shared.reportInstall(config: PostedConfig) async
```

| Field    | Type     | Required | Description                      |
| -------- | -------- | -------- | -------------------------------- |
| `apiKey` | `String` | Yes      | API key from the dashboard, **Posted SDK → API keys**. |
| `appID`  | `String` | Yes      | App ID from the dashboard, **Posted SDK → Apps**.      |

The SDK stores two keys in `UserDefaults`, both prefixed with `Posted_`: the "install reported" flag and a device ID. If the app is deleted and reinstalled, the install is reported again.

## Data collected

The install report is one `POST` to `attr.postedapp.com/api/install`, sent once per install. The backend uses the fields below to match the install to an earlier ad click on the same device.

| Field                          | Source                                   |
| ------------------------------ | ---------------------------------------- |
| `platform`                     | Always `ios`                             |
| `model`, `systemVersion`       | `UIDevice.current`                       |
| `manufacturer`                 | Always `Apple`                           |
| `screenWidth`, `screenHeight`, `scale` | `UIScreen.main`                  |
| `locale`                       | `Locale.preferredLanguages`              |
| `timezone`                     | `TimeZone.current.identifier`            |
| `userAgent`                    | `navigator.userAgent` from a `WKWebView` |
| `timestamp`                    | Current time in milliseconds             |
| `device_id`                    | A random UUID generated once per install |

The SDK never reads the clipboard, never collects the IDFA, and does not request App Tracking Transparency permission.

## Troubleshooting

All SDK logs use the `com.postedapp.posted` subsystem in Console.

| Log line                                            | Meaning                                                                                                |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `Install reported`                                  | Success. Nothing more is sent for this install.                                                        |
| `[Posted:INSTALL_ERROR] Failed to report install: 401` | Wrong `apiKey` or `appID`. Check the credentials in the dashboard.                                 |
| `[Posted:INSTALL_ERROR] Failed to report install: 4xx/5xx` | The backend rejected the report. The SDK retries on the next launch.                            |
| `[Posted:INSTALL_ERROR] Error reporting install: …` | No network. The SDK retries on the next launch.                                                        |
| Nothing logged                                      | The install was already reported on an earlier launch. Delete the app and reinstall to report again.   |

## Example app

See [ExampleUsage](ExampleUsage/README.md) for a minimal Xcode project that calls `reportInstall` on launch.

## Support

Found a bug or have a question? [Open an issue](https://github.com/thepostedapp/posted-sdk-ios/issues).
