// swift-tools-version: 5.9
import PackageDescription

let modules = ["WindowModule", "CaptureModule", "OCRModule", "FinderModule", "ClipboardModule", "NormalizeModule", "OrganizeModule", "UninstallerCore", "UninstallerModule"]

let package = Package(
    name: "PolyMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PolyMacCore", targets: ["PolyMacCore"]),
        .executable(name: "PolyMac", targets: ["PolyMacApp"]),
    ] + modules.map { .library(name: $0, targets: [$0]) },
    targets: [
        .target(name: "PolyMacL10n"),
        .target(name: "PolyMacCore", dependencies: ["PolyMacL10n"]),
        .target(name: "UninstallerCore", dependencies: ["PolyMacL10n"]),
        .testTarget(name: "PolyMacCoreTests", dependencies: ["PolyMacCore"]),
        .testTarget(name: "NormalizeModuleTests", dependencies: ["NormalizeModule"]),
        .testTarget(name: "OrganizeModuleTests", dependencies: ["OrganizeModule"]),
        .testTarget(name: "ClipboardModuleTests", dependencies: ["ClipboardModule"]),
        .testTarget(name: "OCRModuleTests", dependencies: ["OCRModule"]),
        .testTarget(name: "WindowModuleTests", dependencies: ["WindowModule"]),
        .testTarget(name: "FinderModuleTests", dependencies: ["FinderModule"]),
        .testTarget(name: "UninstallerCoreTests", dependencies: ["UninstallerCore", "PolyMacL10n"]),
        .target(name: "CaptureModule", dependencies: ["PolyMacCore", "OCRModule"]),
        .target(name: "UninstallerModule", dependencies: ["PolyMacCore", "UninstallerCore"]),
        // 개발용 OCR 정확도 측정 (scripts/ocr-bench.sh) — 앱 번들에는 들어가지 않는다
        .executableTarget(name: "OCRBench", dependencies: ["OCRModule"]),
        .executableTarget(name: "PolyMacApp", dependencies: ["PolyMacCore"] + modules.map { .target(name: $0) }),
    ] + modules.filter { !["CaptureModule", "UninstallerModule", "UninstallerCore"].contains($0) }.map { .target(name: $0, dependencies: ["PolyMacCore"]) }
)
