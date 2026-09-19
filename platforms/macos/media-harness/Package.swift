// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DisplayMeshMacMediaHarness",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "displaymesh-mac-media-harness",
            targets: ["DisplayMeshMacMediaHarness"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DisplayMeshMacMediaHarness",
            path: "Sources/DisplayMeshMacMediaHarness"
        ),
        .testTarget(
            name: "DisplayMeshMacMediaHarnessTests",
            dependencies: ["DisplayMeshMacMediaHarness"],
            path: "Tests/DisplayMeshMacMediaHarnessTests"
        )
    ]
)
