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
