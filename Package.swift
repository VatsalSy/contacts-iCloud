// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "contacts-iCloud",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "contacts-iCloud",
            targets: ["contacts-iCloud"]
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "contacts-iCloud",
            dependencies: []
        ),
        .testTarget(
            name: "contacts-iCloudTests",
            dependencies: ["contacts-iCloud"]
        ),
    ]
)
