//
//  HoverContentRendererTests.swift
//  CodeEditSourceEditorTests
//

import AppKit
import XCTest
@testable import CodeEditSourceEditor

@MainActor
final class HoverContentRendererTests: XCTestCase {
    func testPlainTextUsesBodyStyle() {
        let attributed = HoverContentRenderer.attributedString(for: .plainText("charge"))

        XCTAssertEqual(attributed.string, "charge")
        XCTAssertEqual((attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 12)
        XCTAssertTrue(
            (attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?
                .isEqual(NSColor.labelColor) == true
        )
    }

    func testSignatureUsesMonospacedFont() {
        let attributed = HoverContentRenderer.attributedString(
            for: [.signature(HoverCode(text: "function charge(): bool", language: "php"))]
        )
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertEqual(font?.pointSize, 12)
        XCTAssertEqual(font?.isFixedPitch, true)
    }

    func testNoticeUsesToneColorForTitle() {
        let attributed = HoverContentRenderer.attributedString(
            for: [.notice(HoverNotice(title: "Deprecated", message: "Use chargeV2().", tone: .warning))]
        )
        let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

        XCTAssertTrue(color?.isEqual(HoverTone.warning.color) == true)
    }

    func testSafeLinksBecomeLinkAttributes() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/docs"))
        let attributed = HoverContentRenderer.attributedString(
            for: [.links([HoverLink(title: "Stripe docs", url: url)])]
        )

        XCTAssertEqual(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL, url)
    }

    func testUnsafeLinksDoNotBecomeLinkAttributes() throws {
        let url = try XCTUnwrap(URL(string: "javascript:alert(1)"))
        let attributed = HoverContentRenderer.attributedString(
            for: [.links([HoverLink(title: "Unsafe", url: url)])]
        )

        XCTAssertNil(attributed.attribute(.link, at: 0, effectiveRange: nil))
    }

    func testContentLengthIsLimited() {
        let paragraph = String(repeating: "a", count: HoverContentRenderer.maxContentLength + 500)
        let attributed = HoverContentRenderer.attributedString(for: .plainText(paragraph))

        XCTAssertLessThanOrEqual(attributed.length, HoverContentRenderer.maxContentLength)
        XCTAssertTrue(attributed.string.hasSuffix("…"))
    }

    func testNarrowWidthIncreasesHeight() {
        let text = String(repeating: "word ", count: 60)
        let wide = HoverContentRenderer.height(for: .plainText(text), width: 500)
        let narrow = HoverContentRenderer.height(for: .plainText(text), width: 200)

        XCTAssertGreaterThan(narrow, wide)
    }

    func testDocumentBlocksAreSeparatedByNewlines() {
        let attributed = HoverContentRenderer.attributedString(
            for: [
                .markdown("Charges a card."),
                .footer("Payment.php:42")
            ]
        )

        XCTAssertEqual(attributed.string, "Charges a card.\nPayment.php:42")
    }

    func testShortContentUsesMinimumCardWidth() {
        let card = HoverCardView(content: .plainText("charge"))

        XCTAssertEqual(card.preferredSize.width, HoverCardView.minWidth)
        XCTAssertGreaterThan(card.preferredSize.height, HoverCardView.inset * 2)
    }

    func testLongContentUsesMaximumDimensions() {
        let text = String(repeating: "word ", count: 2_000)
        let card = HoverCardView(content: .plainText(text))

        XCTAssertEqual(card.preferredSize.width, HoverCardView.maxWidth)
        XCTAssertEqual(card.preferredSize.height, HoverCardView.maxHeight)
    }

    func testCardExposesAccessibilityLabel() {
        let card = HoverCardView(content: .document(HoverDocument(
            header: HoverHeader(title: "charge", systemImageName: "function", tone: .callable)
        )))

        XCTAssertEqual(card.accessibilityLabel(), "Hover: charge")
        XCTAssertEqual(card.accessibilityRole(), .group)
    }

    func testCardContentIsSelectableButNotEditable() {
        let card = HoverCardView(content: .markdown("Charges a card."))
        let textView = firstTextView(in: card)

        XCTAssertEqual(textView?.isSelectable, true)
        XCTAssertEqual(textView?.isEditable, false)
    }

    func testHeaderOnlyCardStaysCompact() {
        let card = HoverCardView(content: .document(HoverDocument(
            header: HoverHeader(
                title: "charge",
                subtitle: "Payment::charge",
                systemImageName: "function",
                tone: .callable,
                badges: [HoverBadge(text: "deprecated", tone: .warning)]
            )
        )))

        XCTAssertGreaterThanOrEqual(card.preferredSize.width, HoverCardView.minWidth)
        XCTAssertLessThanOrEqual(card.preferredSize.width, HoverCardView.maxWidth)
        XCTAssertLessThan(card.preferredSize.height, HoverCardView.maxHeight)
    }

    private func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let textView = firstTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
}
