// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "google_mlkit_language_id",
    platforms: [
        .iOS("15.5")
    ],
    products: [
        .library(
            name: "google-mlkit-language-id",
            targets: ["google_mlkit_language_id"]
        )
    ],
    dependencies: [
        .package(name: "google_mlkit_commons", path: "../google_mlkit_commons"),
        .package(url: "https://github.com/d-date/google-mlkit-swiftpm", from: "9.0.0")
    ],
    targets: [
        .target(
            name: "google_mlkit_language_id",
            dependencies: [
                .product(name: "google-mlkit-commons", package: "google_mlkit_commons"),
                .product(name: "MLKitLanguageID", package: "google-mlkit-swiftpm"),
                .product(name: "MLKitBarcodeScanning", package: "google-mlkit-swiftpm")
            ],
            path: "Classes",
            publicHeadersPath: ".",
            linkerSettings: [
                .linkedFramework("Accelerate")
            ]
        )
    ]
)
