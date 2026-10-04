// swift-tools-version: 5.9
// NotepadSCore: platform-independent logic (Foundation only, never AppKit/UIKit).
// Run the tests with:  swift test --package-path Packages/NotepadSCore
import PackageDescription

let package = Package(
    name: "NotepadSCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "NotepadSCore", targets: ["NotepadSCore"]),
    ],
    targets: [
        .target(name: "NotepadSCore"),
        .testTarget(name: "NotepadSCoreTests", dependencies: ["NotepadSCore"]),
    ]
)
