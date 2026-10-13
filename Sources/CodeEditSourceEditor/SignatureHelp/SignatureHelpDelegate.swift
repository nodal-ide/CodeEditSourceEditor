//
//  SignatureHelpDelegate.swift
//  CodeEditSourceEditor
//

import Foundation

/// Signature/parameter information to display while typing a call.
public struct SignatureHelpInfo {
    /// The full signature, e.g. `view(string $view, array $data = []): Response`.
    public let signature: String
    /// Individual parameter labels, e.g. `["string $view", "array $data = []"]`.
    public let parameters: [String]
    /// Zero-based index of the parameter the cursor is currently in.
    public let activeParameter: Int

    public init(signature: String, parameters: [String], activeParameter: Int) {
        self.signature = signature
        self.parameters = parameters
        self.activeParameter = activeParameter
    }
}

/// A delegate that provides signature help for a call being typed.
@MainActor
public protocol SignatureHelpDelegate: AnyObject {
    /// - Parameters:
    ///   - calleeRange: Range of the called symbol's identifier (e.g. `view` in `$this->view(`).
    ///   - argumentIndex: Zero-based index of the argument the cursor is in.
    ///   - textView: The text view controller.
    /// - Returns: Signature information, or `nil` if unavailable.
    func signatureHelp(
        calleeRange: NSRange,
        argumentIndex: Int,
        textView: TextViewController
    ) async -> SignatureHelpInfo?
}