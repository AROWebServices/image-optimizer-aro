// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OptimizerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OptimizerCore", targets: ["OptimizerCore"])
    ],
    dependencies: [
        // libwebp built from source. ImageIO can decode WebP but cannot encode it,
        // so the app bundles Google's reference encoder.
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", from: "1.6.0")
    ],
    targets: [
        .target(
            name: "OptimizerCore",
            dependencies: [
                .product(name: "libwebp", package: "libwebp-Xcode")
            ]
        ),
        .testTarget(
            name: "OptimizerCoreTests",
            dependencies: ["OptimizerCore"]
        )
    ]
)
