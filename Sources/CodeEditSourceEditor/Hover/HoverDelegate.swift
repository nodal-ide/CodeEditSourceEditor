//
//  HoverDelegate.swift
//  CodeEditSourceEditor
//

import Foundation

/// Information to display in a hover tooltip.
public struct HoverInfo: Equatable {
    /// The structured content shown in the tooltip.
    public let content: HoverContent
    /// Optional range to keep emphasized while hovering.
    public let range: NSRange?

    /// A plain-text representation of ``content``.
    ///
    /// This remains available for compatibility with existing providers and renderers. New code
    /// should use ``content`` directly so rich formatting is preserved.
    public var contents: String {
        content.plainText
    }

    public init(content: HoverContent, range: NSRange? = nil) {
        self.content = content
        self.range = range
    }

    /// Creates plain-text hover information.
    public init(contents: String, range: NSRange? = nil) {
        self.init(content: .plainText(contents), range: range)
    }
}

/// A delegate that provides hover information for an identifier range.
///
/// The source editor calls this after the mouse rests over an identifier for a short
/// dwell period, and displays the returned ``HoverInfo`` in a tooltip.
@MainActor
public protocol HoverDelegate: AnyObject {
    /// - Parameters:
    ///   - range: The range of the hovered identifier in the text view.
    ///   - textView: The text view controller.
    /// - Returns: Hover information, or `nil` if there is nothing to show.
    func hoverInfo(forRange range: NSRange, textView: TextViewController) async -> HoverInfo?
}
