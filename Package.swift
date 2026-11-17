// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OpenGestures",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OpenGestures", targets: ["OpenGestures"]),
    ],
    targets: [
        .target(
            name: "CMultitouch",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .target(
            name: "OpenGesturesCore",
            dependencies: ["CMultitouch"],
            swiftSettings: [
                // Every frame runs under the engine's lock on one thread, so
                // the dynamic exclusivity checks only add cost there. Debug
                // builds and tests keep them.
                .unsafeFlags(["-enforce-exclusivity=unchecked"], .when(configuration: .release)),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "OpenGestures",
            dependencies: ["OpenGesturesCore"]
        ),
        .testTarget(
            name: "OpenGesturesCoreTests",
            dependencies: ["OpenGesturesCore"]
        ),
    ]
)
