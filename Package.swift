// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DashboardReborn",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Dashboard", targets: ["DashboardReborn"])
    ],
    targets: [
        .executableTarget(
            name: "DashboardReborn",
            path: "Sources"
        )
    ]
)
