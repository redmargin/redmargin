// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Redmargin",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "RedmarginCore",
            path: "src/Core"
        ),
        .target(
            name: "RedmarginLib",
            dependencies: ["RedmarginCore"],
            path: "src",
            exclude: ["Core"]
        ),
        .executableTarget(
            name: "Redmargin",
            dependencies: ["RedmarginLib", "RedmarginCore"],
            path: "AppMain"
        ),
        .executableTarget(
            name: "redmargin-server",
            dependencies: [
                "RedmarginCore"
            ],
            path: "Server"
        ),
        .testTarget(
            name: "RedmarginTests",
            dependencies: ["Redmargin", "RedmarginLib", "RedmarginCore"],
            path: "Tests",
            exclude: ["Fixtures", "Scripts", "TEST_LOG.md"]
        )
    ]
)
