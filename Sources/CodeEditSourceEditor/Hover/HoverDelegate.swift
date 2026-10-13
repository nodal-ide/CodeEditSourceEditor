//
//  HoverDelegate.swift
//  CodeEditSourceEditor
//

import Foundation

/// Information to display in a hover tooltip.
public struct HoverInfo {
    /// The text shown in the tooltip. Plain text; may contain line breaks.
    public let contents: String
    /// Optional range to keep emphasized while hovering.
    public let range: NSRange?

    public init(contents: String, range: NSRange? = nil) {
        self.contents = contents
        self.range = range
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