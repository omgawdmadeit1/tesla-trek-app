// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tr3kAr",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "Tr3kAr",
            targets: ["Tr3kARPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "Tr3kARPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/Tr3kARPlugin",
            linkerSettings: [
                .linkedFramework("ARKit"),
                .linkedFramework("SceneKit"),
                .linkedFramework("AVFoundation")
            ])
    ]
)
