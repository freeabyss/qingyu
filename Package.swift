// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Qingyu",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "Qingyu",
            targets: ["Qingyu"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.4.0")
    ],
    targets: [
        .target(
            name: "Qingyu",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Qingyu",
            exclude: [
                "App/QingyuApp.swift",
                "Info.plist",
                "Qingyu.entitlements",
                "Resources/Assets.xcassets",
                "Resources/Localizable.xcstrings"
            ]
        ),
        .testTarget(
            name: "QingyuTests",
            dependencies: ["Qingyu"],
            path: "QingyuTests"
        )
    ]
)
