//
//  HoverURLPolicy.swift
//  CodeEditSourceEditor
//

import Foundation

/// Restricts hover links to schemes that are safe to open from a tooltip.
enum HoverURLPolicy {
    private static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    static func safe(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        guard allowedSchemes.contains(scheme) else { return nil }
        return url
    }
}
