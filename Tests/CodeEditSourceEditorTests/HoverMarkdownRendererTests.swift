//
//  HoverMarkdownRendererTests.swift
//  CodeEditSourceEditorTests
//

import AppKit
import CodeEditLanguages
import XCTest
@testable import CodeEditSourceEditor

@MainActor
final class HoverMarkdownRendererTests: XCTestCase {
    private let theme = Mock.theme()

    func testHeadingsAndParagraphsUseDistinctStyles() throws {
        let attributed = render("# Heading\n\nBody")
        let headingFont = try font(at: "Heading", in: attributed)
        let bodyFont = try font(at: "Body", in: attributed)

        XCTAssertEqual(headingFont.pointSize, 13)
        XCTAssertTrue(headingFont.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(bodyFont.pointSize, 12)
        XCTAssertFalse(bodyFont.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(attributed.string.contains("Heading\nBody"))
    }

    func testEmphasisUsesBoldAndItalicFonts() throws {
        let attributed = render("**Bold** and *italic*")
        let bold = try font(at: "Bold", in: attributed)
        let italic = try font(at: "italic", in: attributed)

        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(italic.fontDescriptor.symbolicTraits.contains(.italic))
    }

    func testInlineCodeUsesMonospacedFont() throws {
        let attributed = render("Use `charge()` here.")
        let code = try font(at: "charge()", in: attributed)

        XCTAssertTrue(code.isFixedPitch)
        XCTAssertNotNil(attributed.attribute(
            .backgroundColor,
            at: (attributed.string as NSString).range(of: "charge()").location,
            effectiveRange: nil
        ))
    }

    func testListsRenderMarkers() throws {
        let attributed = render("- One\n- Two\n\n1. First\n2. Second")

        XCTAssertTrue(attributed.string.contains("• One"))
        XCTAssertTrue(attributed.string.contains("• Two"))
        XCTAssertTrue(attributed.string.contains("1. First"))
        XCTAssertTrue(attributed.string.contains("2. Second"))
    }

    func testQuotesUsePrefixAndSecondaryColor() throws {
        let attributed = render("> Quote")
        let location = (attributed.string as NSString).range(of: "Quote").location
        let color = attributed.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor

        XCTAssertTrue(attributed.string.hasPrefix("│ Quote"))
        XCTAssertTrue(color?.isEqual(NSColor.secondaryLabelColor) == true)
    }

    func testLinksBecomeSafeLinkAttributes() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let attributed = render("[Docs](https://example.com)")
        let location = (attributed.string as NSString).range(of: "Docs").location

        XCTAssertEqual(
            attributed.attribute(.link, at: location, effectiveRange: nil) as? URL,
            url
        )
    }

    func testUnsafeMarkdownLinksAreNotLinked() throws {
        let attributed = render("[Bad](javascript:alert(1))")
        let location = (attributed.string as NSString).range(of: "Bad").location

        XCTAssertNil(attributed.attribute(.link, at: location, effectiveRange: nil))
    }

    func testFencedCodeUsesMonospacedThemeFont() throws {
        let attributed = render("```php\nfunction charge() {}\n```")
        let codeFont = try font(at: "function", in: attributed)

        XCTAssertTrue(codeFont.isFixedPitch)
        XCTAssertNotNil(attributed.attribute(
            .backgroundColor,
            at: (attributed.string as NSString).range(of: "function").location,
            effectiveRange: nil
        ))
    }

    func testFencedCodePreservesIndentation() {
        let attributed = render("```swift\n    let value = 1\n```")

        XCTAssertTrue(attributed.string.contains("    let value = 1"))
    }

    func testFencedCodeAppliesThemeFallbackStyleToEveryRun() {
        let attributed = render("```php\n<?php $value = charge();\n```")
        let fullRange = NSRange(location: 0, length: attributed.length)
        var runCount = 0

        attributed.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            runCount += 1
            XCTAssertNotNil(attributes[.foregroundColor], "Missing foreground color at \(range)")
            XCTAssertNotNil(attributes[.font], "Missing font at \(range)")
        }

        XCTAssertGreaterThan(runCount, 0)
    }

    func testLanguageAliasesResolve() {
        XCTAssertEqual(HoverCodeStyler.language(for: "php")?.id, .php)
        XCTAssertEqual(HoverCodeStyler.language(for: "js")?.id, .javascript)
        XCTAssertEqual(HoverCodeStyler.language(for: "sh")?.id, .bash)
        XCTAssertNil(HoverCodeStyler.language(for: "not-a-language"))
    }

    private func render(_ markdown: String) -> NSAttributedString {
        HoverContentRenderer.attributedString(for: .markdown(markdown), theme: theme)
    }

    private func font(at text: String, in attributed: NSAttributedString) throws -> NSFont {
        let range = (attributed.string as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound)
        return try XCTUnwrap(attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
    }
}
