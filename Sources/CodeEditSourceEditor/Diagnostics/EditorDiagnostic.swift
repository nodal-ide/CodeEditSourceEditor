//
//  EditorDiagnostic.swift
//  CodeEditSourceEditor
//

import Foundation

/// Severity of a native editor diagnostic.
public enum EditorDiagnosticSeverity: Int, Codable, Sendable {
    case error
    case warning
    case info
    case hint
}

/// A diagnostic (problem) within a document, produced by a native language provider.
public struct EditorDiagnostic: Sendable {
    public let range: NSRange
    public let severity: EditorDiagnosticSeverity
    public let message: String
    /// 1-based line number for display, when known.
    public let line: Int?
    /// A stable rule identifier (e.g. `php.complexity`), when the source is rule-based. Used to suppress rules.
    public let ruleID: String?

    public init(
        range: NSRange,
        severity: EditorDiagnosticSeverity,
        message: String,
        line: Int? = nil,
        ruleID: String? = nil
    ) {
        self.range = range
        self.severity = severity
        self.message = message
        self.line = line
        self.ruleID = ruleID
    }
}

/// A delegate that provides diagnostics for the whole document.
@MainActor
public protocol DiagnosticsDelegate: AnyObject {
    func diagnostics(for textView: TextViewController) async -> [EditorDiagnostic]
}