// swift-tools-version: 5.9

import PackageDescription

var targets: [Target] = [
    .target(
        name: "RedmarginCore",
        path: "src/Core"
    ),
    .executableTarget(
        name: "redmargin-server",
        dependencies: [
            "RedmarginCore"
        ],
        path: "Server"
    )
]

#if os(macOS)
targets += [
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
    .testTarget(
        name: "RedmarginTests",
        dependencies: ["Redmargin", "RedmarginLib", "RedmarginCore"],
        path: "Tests",
        exclude: ["Fixtures", "Scripts", "TEST_LOG.md", "Linux"]
    )
]
#endif

#if os(Linux)
targets += [
    .testTarget(
        name: "LinuxServerTests",
        dependencies: ["redmargin-server", "RedmarginCore"],
        path: "Tests/Linux"
    )
]
#endif

let package = Package(
    name: "Redmargin",
    platforms: [
        .macOS(.v14)
    ],
    targets: targets
)
