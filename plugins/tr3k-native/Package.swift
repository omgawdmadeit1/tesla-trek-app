// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tr3kNative",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "Tr3kNative",
            targets: ["Tr3kNativePlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "Tr3kNativePlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/Tr3kNativePlugin",
            linkerSettings: [
                .linkedFramework("ARKit"),
                .linkedFramework("SceneKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("MapKit")
            ])
    ]
)
