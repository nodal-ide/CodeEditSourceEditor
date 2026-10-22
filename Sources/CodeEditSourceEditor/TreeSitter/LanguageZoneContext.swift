import Foundation
import CodeEditLanguages

/// Identifies the active language layer at a document location.
public struct LanguageZoneContext: Hashable, Sendable {
    public let languageID: LanguageID
    public let parentLanguageID: LanguageID?
    public let sourceKey: String?
    public let depth: Int
    public let range: NSRange?

    public init(
        languageID: LanguageID,
        parentLanguageID: LanguageID? = nil,
        sourceKey: String? = nil,
        depth: Int = 0,
        range: NSRange? = nil
    ) {
        self.languageID = languageID
        self.parentLanguageID = parentLanguageID
        self.sourceKey = sourceKey
        self.depth = depth
        self.range = range
    }
}
