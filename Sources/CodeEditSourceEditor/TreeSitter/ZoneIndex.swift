import Foundation
import CodeEditLanguages

/// Identifies an injected zone independently of the ranges it currently occupies.
struct ZoneKey: Hashable {
    let parent: LanguageID
    let language: LanguageID
    let sourceKey: String
}

/// A single language range in the document, owned by a language layer.
struct LanguageSpan {
    let range: NSRange
    let depth: Int
    let sourceKey: String?
    let layer: LanguageLayer
}

/// An index of all injected language spans, sorted by document location.
struct ZoneIndex {
    private(set) var entries: [LanguageSpan] = []
    private var maximumSpanLength: Int = 0

    init(layers: [LanguageLayer] = []) {
        rebuild(layers: layers)
    }

    mutating func rebuild(layers: [LanguageLayer]) {
        entries = layers
            .filter { $0.zoneKey != nil }
            .flatMap { layer in
                layer.ranges.map {
                    LanguageSpan(
                        range: $0,
                        depth: layer.depth,
                        sourceKey: layer.sourceKey,
                        layer: layer
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.range.location != rhs.range.location {
                    return lhs.range.location < rhs.range.location
                }
                return lhs.range.length < rhs.range.length
            }

        maximumSpanLength = entries.reduce(0) { max($0, $1.range.length) }
    }

    /// Returns all spans intersecting the given range, deepest first.
    func spans(intersecting range: NSRange) -> [LanguageSpan] {
        guard range.length > 0, !entries.isEmpty else { return [] }

        let lowerBound = max(0, range.location - maximumSpanLength)
        var low = 0
        var high = entries.count

        while low < high {
            let mid = (low + high) / 2
            if entries[mid].range.location < lowerBound {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let rangeEnd = NSMaxRange(range)
        var result: [LanguageSpan] = []
        var index = low

        while index < entries.count, entries[index].range.location < rangeEnd {
            if range.intersection(entries[index].range) != nil {
                result.append(entries[index])
            }
            index += 1
        }

        return result.sorted(by: Self.isDeeper)
    }

    /// Returns the deepest span containing the given location.
    func deepestSpan(at location: Int) -> LanguageSpan? {
        let range = NSRange(location: location, length: 1)
        return spans(intersecting: range).first
    }

    private static func isDeeper(_ lhs: LanguageSpan, _ rhs: LanguageSpan) -> Bool {
        if lhs.depth != rhs.depth {
            return lhs.depth > rhs.depth
        }
        if lhs.range.length != rhs.range.length {
            return lhs.range.length < rhs.range.length
        }
        return (lhs.sourceKey ?? "") < (rhs.sourceKey ?? "")
    }
}
