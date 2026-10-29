//
//  LineChange.swift
//  CodeEditSourceEditor
//

import Foundation

/// A range of lines in the current document that differs from the last committed version.
///
/// The editor does not know about git; it only receives the ranges to decorate, in the same way it receives
/// breakpoint lines or fold ranges.
public struct LineChange: Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case added
        case modified
        /// Lines were removed at this position. The range is the single line the removed text sat above,
        /// or the last line of the document when the removal was at the end of the file.
        case deleted
    }

    public let kind: Kind

    /// 1-based, inclusive line range in the current document.
    public let lines: ClosedRange<Int>

    public init(kind: Kind, lines: ClosedRange<Int>) {
        self.kind = kind
        self.lines = lines
    }
}
