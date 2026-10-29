//
//  CompletionMatcher.swift
//  CodeEditSourceEditor
//

import Foundation

/// Matches and ranks completion entries for the typed prefix.
///
/// Matching is prefix → word-boundary → substring → subsequence, each with a decreasing base score.
/// Provider order and `sortText` break ties, and `preselect` items lead an empty query.
public enum CompletionMatcher {
    public static let defaultLimit = 200

    public static func ranked(
        _ items: [any CodeSuggestionEntry],
        query: String,
        limit: Int = defaultLimit
    ) -> [any CodeSuggestionEntry] {
        guard limit > 0 else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return preselectFirst(items, limit: limit) }
        let needle = Array(trimmed.lowercased())

        var scored: [(entry: any CodeSuggestionEntry, score: Int, order: String, index: Int)] = []
        scored.reserveCapacity(min(items.count, limit * 2))

        for (index, entry) in items.enumerated() {
            let candidate = entry.filterText ?? entry.label
            guard let score = score(needle: needle, candidate: candidate) else { continue }
            scored.append((entry, score, entry.sortText ?? entry.label, index))
        }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.preselect != rhs.entry.preselect { return lhs.entry.preselect }
            if lhs.order != rhs.order {
                return lhs.order.localizedStandardCompare(rhs.order) == .orderedAscending
            }
            return lhs.index < rhs.index
        }

        return scored.prefix(min(scored.count, limit)).map(\.entry)
    }

    /// Score of `candidate` for a lowercase `needle`, or `nil` when it does not match.
    public static func score(needle: String, candidate: String) -> Int? {
        score(needle: Array(needle.lowercased()), candidate: candidate)
    }

    // MARK: - Private

    private struct PreparedCandidate {
        let lowercase: [Character]
        let boundaries: [Bool]
    }

    private static func prepare(_ candidate: String) -> PreparedCandidate {
        let original = Array(candidate)
        let lowered = Array(candidate.lowercased())
        let comparable = original.count == lowered.count
        var boundaries = [Bool](repeating: false, count: lowered.count)
        for index in lowered.indices {
            guard index > 0 else {
                boundaries[index] = true
                continue
            }
            let previous = comparable ? original[index - 1] : lowered[index - 1]
            let current = comparable ? original[index] : lowered[index]
            if "_-. :/\\".contains(previous) {
                boundaries[index] = true
            } else if previous.isLowercase && current.isUppercase {
                boundaries[index] = true
            }
        }
        return PreparedCandidate(lowercase: lowered, boundaries: boundaries)
    }

    private static func score(needle: [Character], candidate: String) -> Int? {
        guard !needle.isEmpty, !candidate.isEmpty else { return nil }
        let prepared = prepare(candidate)
        let lowered = prepared.lowercase
        guard needle.count <= lowered.count else { return nil }
        let lengthPenalty = min(candidate.count, 40)

        if lowered.starts(with: needle) {
            var bonus = 0
            for index in 0..<needle.count where prepared.boundaries[index] {
                bonus += 6
            }
            return 1000 + bonus - lengthPenalty
        }

        if let boundaryScore = boundaryScore(needle: needle, candidate: prepared) {
            return 820 + boundaryScore - lengthPenalty
        }

        if let offset = substringOffset(needle: needle, candidate: lowered) {
            return 620 - min(offset, 60) * 2 - lengthPenalty
        }

        guard let gaps = subsequenceGaps(needle: needle, candidate: lowered) else { return nil }
        return 400 - min(gaps * 4, 200) - lengthPenalty
    }

    private static func boundaryScore(needle: [Character], candidate: PreparedCandidate) -> Int? {
        var matched = 0
        var score = 0
        var lastIndex = -1
        var needleIndex = 0

        for (index, character) in candidate.lowercase.enumerated() {
            guard needleIndex < needle.count else { break }
            guard character == needle[needleIndex], candidate.boundaries[index] else { continue }
            if lastIndex >= 0 {
                score -= min((index - lastIndex - 1) * 3, 30)
            }
            score += 6
            lastIndex = index
            matched += 1
            needleIndex += 1
        }

        return needleIndex == needle.count && matched > 1 ? score : nil
    }

    private static func substringOffset(needle: [Character], candidate: [Character]) -> Int? {
        guard needle.count <= candidate.count else { return nil }
        let limit = candidate.count - needle.count
        for start in 0...limit {
            var matched = true
            for offset in 0..<needle.count where candidate[start + offset] != needle[offset] {
                matched = false
                break
            }
            if matched { return start }
        }
        return nil
    }

    private static func subsequenceGaps(needle: [Character], candidate: [Character]) -> Int? {
        var gaps = 0
        var lastIndex = -1
        var needleIndex = 0

        for (index, character) in candidate.enumerated() {
            guard needleIndex < needle.count else { break }
            guard character == needle[needleIndex] else { continue }
            if lastIndex >= 0 {
                gaps += index - lastIndex - 1
            }
            lastIndex = index
            needleIndex += 1
        }

        return needleIndex == needle.count ? gaps : nil
    }

    private static func preselectFirst(
        _ items: [any CodeSuggestionEntry],
        limit: Int
    ) -> [any CodeSuggestionEntry] {
        var preselected: [any CodeSuggestionEntry] = []
        var rest: [any CodeSuggestionEntry] = []
        preselected.reserveCapacity(min(items.count, 8))
        rest.reserveCapacity(items.count)
        for item in items {
            if item.preselect {
                preselected.append(item)
            } else {
                rest.append(item)
            }
        }
        return Array((preselected + rest).prefix(limit))
    }
}
