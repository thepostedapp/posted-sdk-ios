# PostedSDK iOS

`PostedSDK` reports app installs to Posted. Posted attributes each install to your ad campaign and reports the conversion to the ad network.

The SDK has one function, `reportInstall(config:)`. Call it on every app launch. It sends the report once per install.

The SDK reports installs only. It does not report purchases, signups or other in-app events.

- [Requirements](#requirements)
- [Get your app ID and API key](#get-your-app-id-and-api-key)
- [1. Install](#1-install)
- [2. Report the install](#2-report-the-install)
- [3. Verify the integration](#3-verify-the-integration)
- [Configuration](#configuration)
- [Privacy](#privacy)
- [Troubleshooting](#troubleshooting)
- [Support](#support)

## Requirements

- iOS 13.0+
- Swift 5.5+
- An app ID and API key from the Posted dashboard. See [Get your app ID and API key](#get-your-app-id-and-api-key).

## Get your app ID and API key

Both come from the Posted dashboard at [app.postedapp.com/dashboard/settings](https://app.postedapp.com/dashboard/settings), under **Posted SDK**.

1. Under **Apps**, click **Add app**, fill in the form and submit it. The dashboard generates the **app ID** (`app_…`) for the new app.
2. Under **API keys**, click **Create key**. Copy the key when it is shown; it is not displayed again.

Pass these as `appID` and `apiKey` in `PostedConfig`. One API key works for all apps in your account.

## 1. Install

### Swift Package Manager

In Xcode, go to `File > Add Package Dependencies...`, enter the repository URL, and add `PostedSDK` to your app target.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/thepostedapp/posted-sdk-ios", from: "1.0.1")
```

### CocoaPods

In your `Podfile`:

```ruby
platform :ios, '13.0'

target 'YourAppTarget' do
  use_frameworks!
  pod 'PostedSDK', '~> 1.0.1'
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

1. Use a **real device** and a build installed from the App Store or TestFlight. Simulators are not attributed.
2. Run the app with a **fresh install**. Deleting the app clears the SDK's storage, so a reinstall reports again.
3. Watch the Console logs for the `com.postedapp.posted` subsystem. On success you'll see `Install reported`. On failure, a line starting with `[Posted:INSTALL_ERROR]` (see [Troubleshooting](#troubleshooting)).

## Configuration

```swift
Posted.shared.reportInstall(config: PostedConfig) async
```

| Field    | Type     | Required | Description                      |
| -------- | -------- | -------- | -------------------------------- |
| `apiKey` | `String` | Yes      | API key from the dashboard, **Posted SDK → API keys**. |
| `appID`  | `String` | Yes      | App ID from the dashboard, **Posted SDK → Apps**.      |

The SDK stores two keys in `UserDefaults`, both prefixed with `Posted_`: the "install reported" flag and a device ID. If the app is deleted and reinstalled, the install is reported again.


## Privacy

The SDK does not use the IDFA, does not read the pasteboard, and requires no App Tracking Transparency prompt. It ships a privacy manifest (`PrivacyInfo.xcprivacy`).

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
