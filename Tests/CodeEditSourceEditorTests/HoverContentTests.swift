//
//  HoverContentTests.swift
//  CodeEditSourceEditorTests
//

import XCTest
@testable import CodeEditSourceEditor

final class HoverContentTests: XCTestCase {
    func testPlainTextCompatibility() {
        let range = NSRange(location: 4, length: 6)
        let info = HoverInfo(contents: "charge", range: range)

        XCTAssertEqual(info.content, .plainText("charge"))
        XCTAssertEqual(info.contents, "charge")
        XCTAssertEqual(info.range, range)
    }

    func testMarkdownContentKeepsSourceAndFlattensToSource() {
        let markdown = "**Charges** a card.\n\n```php\nreturn true;\n```"
        let content = HoverContent.markdown(markdown)

        XCTAssertEqual(content.plainText, markdown)
        XCTAssertFalse(content.isEmpty)
    }

    func testEmptyContent() {
        XCTAssertTrue(HoverContent.plainText("  \n").isEmpty)
        XCTAssertTrue(HoverContent.markdown("").isEmpty)
        XCTAssertTrue(HoverContent.document(HoverDocument(blocks: [.divider])).isEmpty)
    }

    func testDocumentPlainTextFlattensSectionsInOrder() throws {
        let document = try makeDocument()

        let expected = """
        charge

        Payment::charge

        [deprecated] [public]

        Deprecated: Use chargeV2().

        function charge(int $amount): bool

        Charges a card.

        Parameters
        $amount (int) — Amount in cents.
        $options (array<string, mixed>)

        Stripe docs: https://example.com
        Related guide

        @since 1.2.0

        Payment.php:42
        """

        XCTAssertEqual(document.plainText, expected)
        XCTAssertEqual(HoverContent.document(document).plainText, expected)
    }

    func testDefinitionItemPlainTextFormatsAvailableFields() {
        XCTAssertEqual(
            HoverDefinitionItem(term: "$amount", type: "int", description: "Amount.").plainText,
            "$amount (int) — Amount."
        )
        XCTAssertEqual(
            HoverDefinitionItem(term: "$amount", description: "Amount.").plainText,
            "$amount — Amount."
        )
        XCTAssertEqual(
            HoverDefinitionItem(type: "bool", description: "Whether it worked.").plainText,
            "bool — Whether it worked."
        )
        XCTAssertEqual(HoverDefinitionItem(term: "$amount").plainText, "$amount")
    }

    func testDocumentWithOnlyHeaderIsNotEmpty() {
        let content = HoverContent.document(
            HoverDocument(header: HoverHeader(title: "Payment"))
        )

        XCTAssertFalse(content.isEmpty)
        XCTAssertEqual(content.plainText, "Payment")
    }

    private func makeDocument() throws -> HoverDocument {
        HoverDocument(header: makeHeader(), blocks: try makeBlocks())
    }

    private func makeHeader() -> HoverHeader {
        HoverHeader(
            title: "charge",
            subtitle: "Payment::charge",
            systemImageName: "function",
            tone: .callable,
            badges: [
                HoverBadge(text: "deprecated", tone: .warning),
                HoverBadge(text: "public")
            ]
        )
    }

    private func makeBlocks() throws -> [HoverBlock] {
        let definitionList = HoverDefinitionList(
            title: "Parameters",
            items: [
                HoverDefinitionItem(
                    term: "$amount",
                    type: "int",
                    description: "Amount in cents."
                ),
                HoverDefinitionItem(term: "$options", type: "array<string, mixed>")
            ]
        )
        let links = [
            HoverLink(
                title: "Stripe docs",
                url: try XCTUnwrap(URL(string: "https://example.com"))
            ),
            HoverLink(title: "Related guide")
        ]

        return [
            .notice(HoverNotice(title: "Deprecated", message: "Use chargeV2().", tone: .warning)),
            .signature(HoverCode(text: "function charge(int $amount): bool", language: "php")),
            .markdown("Charges a card."),
            .definitionList(definitionList),
            .links(links),
            .metadata([HoverMetadataItem(label: "@since", value: "1.2.0")]),
            .divider,
            .footer("Payment.php:42")
        ]
    }
}
