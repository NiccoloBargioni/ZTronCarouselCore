// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZTronCarouselCore",
    platforms: [.iOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ZTronCarouselCore",
            targets: ["ZTronCarouselCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SnapKit/SnapKit", branch: "develop"),
        .package(url: "https://github.com/yuriiik/ISVImageScrollView", branch: "master"),
        .package(url: "https://github.com/NiccoloBargioni/ZTronVideoPlayer", branch: "main"),
        .package(url: "https://github.com/NiccoloBargioni/ZTronObservation", branch: "bugfix/threadSafety"),
        .package(url: "https://github.com/Juanpe/SkeletonView", branch: "main")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ZTronCarouselCore",
            dependencies: [
                .product(name: "SnapKit", package: "SnapKit"),
                .product(name: "ISVImageScrollView", package: "ISVImageScrollView"),
                .product(name: "ZTronVideoPlayer", package: "ZTronVideoPlayer"),
                .product(name: "ZTronObservation", package: "ZTronObservation"),
                .product(name: "SkeletonView", package: "SkeletonView")
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete")
            ]
        ),
        .testTarget(
            name: "ZTronCarouselCoreTests",
            dependencies: [
                "ZTronCarouselCore"
            ]
        ),
    ]
)
