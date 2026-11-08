// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HyprMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "hyprmac", targets: ["HyprMac"]),
    ],
    targets: [
        // Pure logic (layout tree, config parser, geometry) — unit-testable.
        .target(name: "HyprMacCore"),
        // AppKit / Accessibility front-end.
        .executableTarget(
            name: "HyprMac",
            dependencies: ["HyprMacCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(name: "HyprMacCoreTests", dependencies: ["HyprMacCore"]),
    ]
)
