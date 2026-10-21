# Highlighting Performance Counters

## Overview

In Debug builds, tree-sitter highlighting records lightweight counters in `HighlightingMetrics.shared`.
They are intended for regression tests and local profiling, not production telemetry. Call
`HighlightingMetrics.shared.reset()` before a scenario and read `HighlightingMetrics.shared.current`
afterward.

The counters are cumulative until reset:

- `highlightQueries`: number of visible/chunk highlight queries.
- `layersVisited`: language layers visited by those queries.
- `highlightQueryIntersections`: zones intersected by visible queries.
- `injectionQueries`: injection discovery queries.
- `invalidatedRanges`: highlight ranges invalidated by edits.
- `dirtyLayers`: layers marked dirty by an edit.
- `dirtyRanges`: layer ranges intersecting the edited region.
- `parsedLayers`: layers reparsed after an edit.
- `maxLayerCount` / `maxRangeCount`: largest observed layer/range totals.

## Reading Results

A healthy visible query visits a small number of layers regardless of document size. A healthy edit
has `dirtyLayers`, `dirtyRanges`, and `parsedLayers` proportional to the edited zone, not the whole
document. `test_editingOneIslandParsesOnlyDirtyLayers` and `test_scrollingVisibleChunksStayBounded`
enforce these invariants on the large mixed-PHP fixture with counter thresholds rather than wall-clock
assertions.

`test_baselineLargeMixedPHP` prints Debug timings for open, visible query, five scroll chunks, one
edit, and language change. Timings are diagnostic only and are not asserted in CI.

## Fixture Thresholds

Thresholds live next to `HighlightingFixtures`:

- visible chunk length: 4,000 UTF-16 units
- visible-layer limit: 20
- visible-query intersection limit: 400
- injection-query limit per edit: 4

Update these only with a measured reason; they are contract checks for zone indexing and dirty-edit
invalidation.
