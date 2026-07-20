// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "contacts-iCloud",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "contacts-iCloud",
            targets: ["contacts-iCloud"]
        ),
        .executable(
            name: "google-vcf-export",
            targets: ["google-vcf-export"]
        ),
        .executable(
            name: "sync-to-icloud",
            targets: ["sync-to-icloud"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
        .package(url: "https://github.com/JohnSundell/Files", from: "4.0.0")
    ],
    targets: [
        .executableTarget(
            name: "contacts-iCloud",
            dependencies: []
        ),
        .executableTarget(
            name: "google-vcf-export",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                "SwiftSoup",
                "Files"
            ]
        ),
        .executableTarget(
            name: "sync-to-icloud",
            dependencies: [
                "Files"
            ]
        ),
        .testTarget(
            name: "contacts-iCloudTests",
            dependencies: ["contacts-iCloud"]
        ),
    ]
)
