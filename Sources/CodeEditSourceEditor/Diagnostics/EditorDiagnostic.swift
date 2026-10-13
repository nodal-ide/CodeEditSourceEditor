//
//  EditorDiagnostic.swift
//  CodeEditSourceEditor
//

import Foundation

/// Severity of a native editor diagnostic.
public enum EditorDiagnosticSeverity: Int, Sendable {
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

    public init(range: NSRange, severity: EditorDiagnosticSeverity, message: String) {
        self.range = range
        self.severity = severity
        self.message = message
    }
}

/// A delegate that provides diagnostics for the whole document.
@MainActor
public protocol DiagnosticsDelegate: AnyObject {
    func diagnostics(for textView: TextViewController) async -> [EditorDiagnostic]
}