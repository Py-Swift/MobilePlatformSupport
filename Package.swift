// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MobilePlatformSupport",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MobilePlatformSupport",
            targets: ["MobilePlatformSupport"]),
        .library(
            name: "MarkdownReportGenerator",
            targets: ["MarkdownReportGenerator"]),
        .executable(
            name: "mobile-wheels-checker",
            targets: ["MobileWheelsChecker"]),
        .executable(
            name: "dependency-checker",
            targets: ["DependencyChecker"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/realm/realm-swift", exact: "10.54.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MobilePlatformSupport",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "MarkdownReportGenerator",
            dependencies: ["MobilePlatformSupport"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "MobileWheelsChecker",
            dependencies: [
                "MobilePlatformSupport",
                "MarkdownReportGenerator",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "RealmSwift", package: "realm-swift"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "DependencyChecker",
            dependencies: ["MobilePlatformSupport"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
