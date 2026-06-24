# PostedSDK iOS Example

This example demonstrates all three link types supported by the PostedSDK:

- **Deferred link** — resolved on first launch after install
- **Universal Link** — http/https link handled while the app is installed
- **Custom scheme link** — e.g. `myapp://product/42`

## Prerequisites

You need a Posted account with an app configured. Sign up at [godetour.dev](https://godetour.dev/auth/signup) if you haven't already.

## Setup

### 1. Open the project

Open `DetourExampleAppProject/DetourExampleApp.xcodeproj` in Xcode.

### 2. Replace placeholders

The following placeholders appear in `AppDelegate.swift`, `Info.plist`, and `DetourExampleApp.entitlements`:

| Placeholder                    | Where to find it                        | Example value              |
| ------------------------------ | --------------------------------------- | -------------------------- |
| `<YOUR_POSTED_API_KEY>`        | Posted dashboard → your app → API key   | `dtk_live_abc123`          |
| `<YOUR_POSTED_APP_ID>`         | Posted dashboard → your app → App ID    | `app_xyz789`               |
| `<YOUR_BUNDLE_IDENTIFIER>`     | Xcode → target → General → Bundle ID   | `com.company.exampleapp`   |
| `<YOUR_CUSTOM_SCHEME>`         | Pick any scheme for your app            | `myapp`                    |
| `<YOUR_UNIVERSAL_LINK_DOMAIN>` | Posted dashboard → your app → domain   | `example.godetour.link`    |

### 3. Configure URL scheme

In `Info.plist`, replace `<YOUR_CUSTOM_SCHEME>` under `CFBundleURLSchemes` with your chosen scheme.

### 4. Configure Associated Domains

In `DetourExampleApp.entitlements`, replace `<YOUR_UNIVERSAL_LINK_DOMAIN>` under `Associated Domains` with your Posted domain (e.g. `applinks:example.godetour.link`).

### 5. Run

Select a simulator or device and press **Run** in Xcode.

## Testing

| Scenario        | How to trigger                                                             |
| --------------- | -------------------------------------------------------------------------- |
| Deferred link   | Create a link in the Posted dashboard, open it on a fresh install          |
| Universal Link  | Open `https://<YOUR_UNIVERSAL_LINK_DOMAIN>/...` on a device with the app  |
| Custom scheme   | Open `<YOUR_CUSTOM_SCHEME>://...` from Safari or another app               |
