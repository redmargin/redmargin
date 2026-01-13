// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Redmargin",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "RedmarginLib",
            path: "src"
        ),
        .executableTarget(
            name: "Redmargin",
            dependencies: ["RedmarginLib"],
            path: "AppMain"
        ),
        .testTarget(
            name: "RedmarginTests",
            dependencies: ["RedmarginLib"],
            path: "Tests",
            exclude: ["Fixtures", "Scripts", "TEST_LOG.md"]
        )
    ]
)
