# PostedSDK iOS Example

This example demonstrates all three link types supported by the PostedSDK:

- **Deferred link** — resolved on first launch after install
- **Universal Link** — http/https link handled while the app is installed
- **Custom scheme link** — e.g. `posted://product/42` (the example app pre-registers the `posted` scheme)

## Prerequisites

You need a Posted account with an app configured. Sign up at [postedapp.com](https://postedapp.com) <!-- TODO(B3): update once backend/site domain confirmed --> if you haven't already.

## Setup

### 1. Open the project

Open `PostedExampleAppProject/PostedExampleApp.xcodeproj` in Xcode.

### 2. Replace placeholders

The following placeholders appear in `AppDelegate.swift`, `Info.plist`, and `PostedExampleApp.entitlements`:

| Placeholder                    | Where to find it                        | Example value              |
| ------------------------------ | --------------------------------------- | -------------------------- |
| `<YOUR_POSTED_API_KEY>`        | Posted dashboard → your app → API key   | `posted_live_abc123`       |
| `<YOUR_POSTED_APP_ID>`         | Posted dashboard → your app → App ID    | `app_xyz789`               |
| `<YOUR_BUNDLE_IDENTIFIER>`     | Xcode → target → General → Bundle ID   | `com.company.exampleapp`   |
| `<YOUR_UNIVERSAL_LINK_DOMAIN>` | Posted dashboard → your app → domain   | `example.godetour.link` <!-- TODO(B4): short-link/UL domain pending; Universal Links deferred for v1 --> |

The example app's `Info.plist` ships with the `posted` URL scheme already registered
(so `posted://…` opens the app). Register your own scheme there for your real app.

### 3. Configure URL scheme

`Info.plist` already registers the `posted` scheme under `CFBundleURLSchemes`, so
`posted://…` links open the app out of the box. To use your own scheme instead, replace
`posted` with your chosen scheme.

### 4. Configure Associated Domains

In `PostedExampleApp.entitlements`, replace `<YOUR_UNIVERSAL_LINK_DOMAIN>` under `Associated Domains` with your Posted domain (e.g. `applinks:example.godetour.link`). <!-- TODO(B4): short-link/UL domain pending; Universal Links deferred for v1 -->

### 5. Run

Select a simulator or device and press **Run** in Xcode.

## Testing

| Scenario        | How to trigger                                                             |
| --------------- | -------------------------------------------------------------------------- |
| Deferred link   | Create a link in the Posted dashboard, open it on a fresh install          |
| Universal Link  | Open `https://<YOUR_UNIVERSAL_LINK_DOMAIN>/...` on a device with the app  |
| Custom scheme   | Open `posted://product/42` from Safari or another app                     |
