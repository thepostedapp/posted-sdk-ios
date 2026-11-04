// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.
// (5.6+ is required by swift-docc-plugin.)

import PackageDescription

let package = Package(
    name: "PostedSDK",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "PostedSDK",
            targets: ["PostedSDK"]
        ),
    ],
    dependencies: [
        // Dev/build tooling only — generates the API reference in CI. Not needed to build or
        // consume the PostedSDK library itself.
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "PostedSDK",
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "PostedSDKTests",
            dependencies: ["PostedSDK"],
            path: "Tests/PostedSDKTests"
        ),
    ]
)
