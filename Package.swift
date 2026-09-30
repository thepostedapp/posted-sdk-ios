// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.
// (Bumped from 5.5 to 5.6 for POS-617 — swift-docc-plugin requires tools-version 5.6+.)

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
        // Dev/build tooling only — generates the API reference in CI (POS-617). Not needed to
        // build or consume the PostedSDK library itself.
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "PostedSDK"
        ),
        .testTarget(
            name: "PostedSDKTests",
            dependencies: ["PostedSDK"],
            path: "Tests/PostedSDKTests",
            resources: [
                .copy("Fixtures/posted-backend-contract.yaml"),
            ]
        ),
    ]
)
