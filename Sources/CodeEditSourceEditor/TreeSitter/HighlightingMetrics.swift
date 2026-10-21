import Foundation

final class HighlightingMetrics: @unchecked Sendable {
    struct Snapshot: Equatable {
        var layersVisited = 0
        var injectionQueries = 0
        var highlightQueries = 0
        var highlightQueryIntersections = 0
        var invalidatedRanges = 0
        var maxLayerCount = 0
        var maxRangeCount = 0
    }

    static let shared = HighlightingMetrics()

    private let lock = NSLock()
    private var snapshot = Snapshot()

    var current: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        snapshot = Snapshot()
    }

    func recordState(layerCount: Int, rangeCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        snapshot.maxLayerCount = max(snapshot.maxLayerCount, layerCount)
        snapshot.maxRangeCount = max(snapshot.maxRangeCount, rangeCount)
    }

    func recordInjectionQuery() {
        lock.lock()
        defer { lock.unlock() }
        snapshot.injectionQueries += 1
    }

    func recordHighlightQuery(layersVisited: Int, intersections: Int) {
        lock.lock()
        defer { lock.unlock() }
        snapshot.highlightQueries += 1
        snapshot.layersVisited += layersVisited
        snapshot.highlightQueryIntersections += intersections
    }

    func recordInvalidatedRanges(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        snapshot.invalidatedRanges += count
    }
}
