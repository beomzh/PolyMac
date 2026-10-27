// swift-tools-version: 5.9
import PackageDescription

let modules = ["WindowModule", "CaptureModule", "OCRModule", "FinderModule", "ClipboardModule", "NormalizeModule", "OrganizeModule", "UninstallerCore"]

let package = Package(
    name: "PolyMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PolyMacCore", targets: ["PolyMacCore"])
    ] + modules.map { .library(name: $0, targets: [$0]) },
    targets: [
        .target(name: "PolyMacCore"),
        .testTarget(name: "PolyMacCoreTests", dependencies: ["PolyMacCore"]),
        .testTarget(name: "NormalizeModuleTests", dependencies: ["NormalizeModule"]),
        .testTarget(name: "OrganizeModuleTests", dependencies: ["OrganizeModule"]),
    ] + modules.map { .target(name: $0, dependencies: ["PolyMacCore"]) }
)
