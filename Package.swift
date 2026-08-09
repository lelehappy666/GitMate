// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GitMate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GitMateCore", targets: ["GitMateCore"]),
        .executable(name: "GitMate", targets: ["GitMateApp"])
    ],
    targets: [
        .target(
            name: "GitMateCore",
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "GitMateApp",
            dependencies: ["GitMateCore"]
        ),
        .executableTarget(
            name: "GitMateCoreTestsRunner",
            dependencies: ["GitMateCore"],
            path: "Tests/GitMateCoreTests",
            swiftSettings: [
                .define(
                    "GITMATE_TESTING_INTERNALS",
                    .when(configuration: .debug)
                )
            ]
        )
    ]
)
