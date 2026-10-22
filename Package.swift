// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodeEditSourceEditor",
    platforms: [.macOS(.v13)],
    products: [
        // A source editor with useful features for code editing.
        .library(
            name: "CodeEditSourceEditor",
            targets: ["CodeEditSourceEditor"]
        )
    ],
    dependencies: [
        // A fast, efficient, text view for code.
        .package(
            url: "https://github.com/nodal-ide/CodeEditTextView.git",
            revision: "eb9820c2384ce5f6661d29846a147390f6ff538e"
        ),
        // tree-sitter languages
        .package(
            url: "https://github.com/nodal-ide/CodeEditLanguages.git",
            revision: "497fc6a7c5c0042bf3c0d2b907be6b145a963364"
        ),
        // CodeEditSymbols
        .package(
            url: "https://github.com/nodal-ide/CodeEditSymbols.git",
            revision: "247200521218bc1cc0ec962012c407a5ef8460d7"
        ),
        // Rules for indentation, pair completion, whitespace
        .package(
            url: "https://github.com/ChimeHQ/TextFormation",
            from: "0.8.2"
        ),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0")
    ],
    targets: [
        // A source editor with useful features for code editing.
        .target(
            name: "CodeEditSourceEditor",
            dependencies: [
                "CodeEditTextView",
                "CodeEditLanguages",
                "TextFormation",
                "CodeEditSymbols"
            ]
        ),

        // Tests for the source editor
        .testTarget(
            name: "CodeEditSourceEditorTests",
            dependencies: [
                "CodeEditSourceEditor",
                "CodeEditLanguages",
                .product(name: "CustomDump", package: "swift-custom-dump")
            ]
        ),
    ]
)
