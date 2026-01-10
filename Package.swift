// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RedMargin",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "RedMargin",
            path: "src"
        ),
        .testTarget(
            name: "RedMarginTests",
            dependencies: ["RedMargin"],
            path: "Tests"
        )
    ]
)
