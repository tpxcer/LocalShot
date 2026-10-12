// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "LocalShot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LocalShotCore", targets: ["LocalShotCore"]),
        .library(name: "LocalShotEditing", targets: ["LocalShotEditing"]),
        .library(name: "LocalShotVision", targets: ["LocalShotVision"]),
        .library(name: "LocalShotTranslation", targets: ["LocalShotTranslation"]),
        .library(name: "LocalShotBeautification", targets: ["LocalShotBeautification"]),
        .library(name: "LocalShotScrolling", targets: ["LocalShotScrolling"]),
        .library(name: "LocalShotHotkeys", targets: ["LocalShotHotkeys"]),
        .library(name: "LocalShotHistoryIndex", targets: ["LocalShotHistoryIndex"]),
        .library(name: "LocalShotUpdater", targets: ["LocalShotUpdater"]),
        .executable(name: "LocalShot", targets: ["LocalShot"]),
        .executable(name: "LocalShotCoreCheck", targets: ["LocalShotCoreCheck"]),
        .executable(name: "LocalShotEditingCheck", targets: ["LocalShotEditingCheck"]),
        .executable(name: "LocalShotOCRCheck", targets: ["LocalShotOCRCheck"]),
        .executable(name: "LocalShotTranslationCheck", targets: ["LocalShotTranslationCheck"]),
        .executable(name: "LocalShotBeautificationCheck", targets: ["LocalShotBeautificationCheck"]),
        .executable(name: "LocalShotScrollingCheck", targets: ["LocalShotScrollingCheck"]),
        .executable(name: "LocalShotHistoryIndexCheck", targets: ["LocalShotHistoryIndexCheck"]),
        .executable(name: "LocalShotHotKeyCheck", targets: ["LocalShotHotKeyCheck"]),
        .executable(name: "LocalShotUpdaterCheck", targets: ["LocalShotUpdaterCheck"]),
        .executable(name: "LocalShotUpdaterLiveCheck", targets: ["LocalShotUpdaterLiveCheck"])
    ],
    targets: [
        .target(name: "LocalShotCore"),
        .target(
            name: "LocalShotSystemScreenshot",
            dependencies: ["LocalShotCore"]
        ),
        .target(
            name: "LocalShotEditing",
            dependencies: ["LocalShotCore"]
        ),
        .target(name: "LocalShotVision"),
        .target(
            name: "LocalShotTranslation",
            dependencies: ["LocalShotVision"]
        ),
        .target(name: "LocalShotBeautification"),
        .target(name: "LocalShotScrolling"),
        .target(
            name: "LocalShotHotkeys",
            dependencies: ["LocalShotCore"]
        ),
        .target(
            name: "LocalShotHistoryIndex",
            dependencies: ["LocalShotVision"]
        ),
        .target(name: "LocalShotUpdater"),
        .executableTarget(
            name: "LocalShot",
            dependencies: [
                "LocalShotCore",
                "LocalShotSystemScreenshot",
                "LocalShotHotkeys",
                "LocalShotEditing",
                "LocalShotVision",
                "LocalShotTranslation",
                "LocalShotBeautification",
                "LocalShotScrolling",
                "LocalShotHistoryIndex",
                "LocalShotUpdater"
            ]
        ),
        .executableTarget(
            name: "LocalShotCoreCheck",
            dependencies: ["LocalShotCore", "LocalShotSystemScreenshot"]
        ),
        .executableTarget(
            name: "LocalShotEditingCheck",
            dependencies: ["LocalShotEditing"]
        ),
        .executableTarget(
            name: "LocalShotOCRCheck",
            dependencies: ["LocalShotVision"]
        ),
        .executableTarget(
            name: "LocalShotTranslationCheck",
            dependencies: ["LocalShotTranslation"]
        ),
        .executableTarget(
            name: "LocalShotBeautificationCheck",
            dependencies: ["LocalShotBeautification"]
        ),
        .executableTarget(
            name: "LocalShotScrollingCheck",
            dependencies: ["LocalShotScrolling"]
        ),
        .executableTarget(
            name: "LocalShotHistoryIndexCheck",
            dependencies: ["LocalShotHistoryIndex"]
        ),
        .executableTarget(
            name: "LocalShotHotKeyCheck",
            dependencies: ["LocalShotCore", "LocalShotHotkeys"]
        ),
        .executableTarget(
            name: "LocalShotUpdaterCheck",
            dependencies: ["LocalShotUpdater"]
        ),
        .executableTarget(
            name: "LocalShotUpdaterLiveCheck",
            dependencies: ["LocalShotUpdater"]
        )
    ]
)
