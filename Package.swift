// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Redmargin",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Redmargin",
            path: "src"
        ),
        .testTarget(
            name: "RedmarginTests",
            dependencies: ["Redmargin"],
            path: "Tests",
            exclude: ["Fixtures"]
        )
    ]
)
