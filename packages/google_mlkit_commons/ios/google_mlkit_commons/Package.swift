// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "google_mlkit_commons",
    platforms: [
        .iOS("15.5")
    ],
    products: [
        .library(
            name: "google-mlkit-commons",
            targets: ["google_mlkit_commons"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "google_mlkit_commons",
            dependencies: [],
            path: ".",
            exclude: [
                "Classes/MLKVisionImage+FlutterPlugin.m",
                "Classes/GenericModelManager.h",
                "Classes/GenericModelManager.m"
            ],
            sources: ["Classes"],
            publicHeadersPath: "include"
        )
    ]
)
