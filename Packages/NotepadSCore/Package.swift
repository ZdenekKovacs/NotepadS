// swift-tools-version: 5.9
// NotepadSCore: platform-independent logic (Foundation only, never AppKit/UIKit).
// Run the tests with:  swift test --package-path Packages/NotepadSCore
import PackageDescription

let package = Package(
    name: "NotepadSCore",
    // User-facing strings (encoding names, error messages) are localizable; English only for now.
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "NotepadSCore", targets: ["NotepadSCore"]),
    ],
    targets: [
        .target(name: "NotepadSCore", resources: [.process("Resources")]),
        .testTarget(name: "NotepadSCoreTests", dependencies: ["NotepadSCore"]),
    ]
)
