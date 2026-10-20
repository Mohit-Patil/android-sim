// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PhoneSwitcher",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "phones", targets: ["phones"]),
        .executable(name: "PhoneSwitcherApp", targets: ["PhoneSwitcherApp"]),
    ],
    targets: [
        .target(name: "PhoneCore"),
        .executableTarget(name: "phones", dependencies: ["PhoneCore"]),
        .executableTarget(name: "PhoneSwitcherApp", dependencies: ["PhoneCore"]),
        .testTarget(name: "PhoneCoreTests", dependencies: ["PhoneCore"]),
    ]
)
