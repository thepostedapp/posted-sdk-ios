# PostedSDK iOS Example

A minimal app that calls `reportInstall` on launch and shows a log of what happened.

## Prerequisites

You need a Posted account with an app configured. See [Create an app & find your credentials](https://github.com/thepostedapp/posted-sdk-admin/blob/main/README.md#create-an-app--find-your-credentials).

## Setup

1. Open `PostedExampleAppProject/PostedExampleApp.xcodeproj` in Xcode.
2. In `AppDelegate.swift`, replace the two placeholders:

   | Placeholder             | Where to find it                      |
   | ----------------------- | ------------------------------------- |
   | `<YOUR_POSTED_API_KEY>` | Posted dashboard → your app → API key |
   | `<YOUR_POSTED_APP_ID>`  | Posted dashboard → your app → App ID  |

3. Select a simulator or device and press **Run**.

## What to expect

On the first launch the SDK posts the install report. Open Console, filter by the
`com.postedapp.posted` subsystem, and look for `Install reported`. Later launches send nothing.
Delete the app and run it again to report a fresh install.
