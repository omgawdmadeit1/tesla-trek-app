// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tr3kNative",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "Tr3kNative",
            targets: ["Tr3kNativePlugin"]),
        .library(
            name: "Tr3kActivityKit",
            targets: ["Tr3kActivityKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "Tr3kActivityKit",
            path: "ios/Sources/Tr3kActivityKit",
            swiftSettings: [
                // The Xcode 26 driver does not accept -disable-autolink-framework
                // itself. Pass it to the frontend so ActivityKit stays a weak link
                // and an iOS 15 launch does not hard-require the framework.
                .unsafeFlags([
                    "-Xfrontend", "-disable-autolink-framework",
                    "-Xfrontend", "ActivityKit"
                ])
            ],
            linkerSettings: [
                .unsafeFlags(["-weak_framework", "ActivityKit"])
            ]
        ),
        .target(
            name: "Tr3kNativePlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                "Tr3kActivityKit"
            ],
            path: "ios/Sources/Tr3kNativePlugin",
            linkerSettings: [
                .linkedFramework("ARKit"),
                .linkedFramework("SceneKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("MapKit"),
                .linkedFramework("LinkPresentation")
            ])
    ]
)
