// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Brim",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Brim", targets: ["Brim"]),
        .library(name: "BrimCore", targets: ["BrimCore"]),
        .library(name: "BrimKit", targets: ["BrimKit"]),
    ],
    targets: [
        // 不碰界面的部分：收纳的设置、松的像素图、界面语言。可以单独测。
        .target(name: "BrimCore"),
        // 应用本身：顶部面板、收纳、设置窗口。留了两个接口给扩展（见 Extensions.swift）。
        .target(name: "BrimKit", dependencies: ["BrimCore"]),
        // 开源版的入口：不装任何扩展
        .executableTarget(name: "Brim", dependencies: ["BrimKit"]),
        .testTarget(name: "BrimCoreTests", dependencies: ["BrimCore"]),
    ]
)
