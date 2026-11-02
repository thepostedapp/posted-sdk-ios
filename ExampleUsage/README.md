# PostedSDK iOS Example

A minimal app that calls `reportInstall` on launch and shows a log of what happened.

## Prerequisites

You need a Posted account. Create an app and an API key at [app.postedapp.com/dashboard/settings](https://app.postedapp.com/dashboard/settings) under **Posted SDK** (see the main README's [Get your app ID and API key](../README.md#get-your-app-id-and-api-key)).

## Setup

1. Open `PostedExampleAppProject/PostedExampleApp.xcodeproj` in Xcode.
2. In `AppDelegate.swift`, replace the two placeholders:

   | Placeholder             | Where to find it                      |
   | ----------------------- | ------------------------------------- |
   | `<YOUR_POSTED_API_KEY>` | Dashboard → Settings → Posted SDK → API keys → Create key |
   | `<YOUR_POSTED_APP_ID>`  | Dashboard → Settings → Posted SDK → Apps → Add app       |

3. Select a simulator or device and press **Run**.

## What to expect

On the first launch the SDK posts the install report. Open Console, filter by the
`com.postedapp.posted` subsystem, and look for `Install reported`. Later launches send nothing.
Delete the app and run it again to report a fresh install.
