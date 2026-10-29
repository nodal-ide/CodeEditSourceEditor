//
//  ChangeRibbonView.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditTextView

/// Draws uncommitted line changes as a narrow bar at the trailing edge of the gutter.
///
/// Only the lines intersecting the dirty rect are considered: the change list is sorted and non-overlapping, so a
/// binary search finds the first visible block and the loop stops as soon as it passes the last visible line. The
/// view is non-interactive; clicks fall through to the gutter.
final class ChangeRibbonView: NSView {
    static let barWidth: CGFloat = 3
    static let padding: CGFloat = 4

    /// Total width this view needs when visible.
    static var contentWidth: CGFloat {
        barWidth + padding
    }

    private static let addedColor = NSColor.systemGreen.withAlphaComponent(0.85)
    private static let modifiedColor = NSColor.systemBlue.withAlphaComponent(0.85)
    private static let deletedColor = NSColor.systemRed.withAlphaComponent(0.85)

    private weak var textView: TextView?

    var changes: [LineChange] = [] {
        didSet {
            guard changes != oldValue else { return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    init(controller: TextViewController) {
        self.textView = controller.textView
        super.init(frame: .zero)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !changes.isEmpty,
              let layoutManager = textView?.layoutManager,
              let firstVisible = layoutManager.textLineForPosition(dirtyRect.minY) else {
            return
        }
        let lastVisibleLine = layoutManager.textLineForPosition(dirtyRect.maxY)?.index ?? firstVisible.index

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: dirtyRect).addClip()

        var index = firstIndex(endingAtOrAfter: firstVisible.index + 1)
        while index < changes.count {
            let change = changes[index]
            index += 1
            guard change.lines.lowerBound <= lastVisibleLine + 1 else { break }
            guard let start = layoutManager.textLineForIndex(change.lines.lowerBound - 1) else { continue }
            guard start.yPos <= dirtyRect.maxY else { break }

            switch change.kind {
            case .deleted:
                drawDeletionMarker(at: start.yPos, height: start.height)
            case .added, .modified:
                let end = layoutManager.textLineForIndex(change.lines.upperBound - 1) ?? start
                let rect = CGRect(
                    x: bounds.width - Self.barWidth,
                    y: start.yPos,
                    width: Self.barWidth,
                    height: max(end.yPos + end.height - start.yPos, 2)
                )
                (change.kind == .added ? Self.addedColor : Self.modifiedColor).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawDeletionMarker(at yPos: CGFloat, height: CGFloat) {
        let size = min(Self.barWidth * 1.8, height)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: bounds.width, y: yPos))
        path.line(to: CGPoint(x: bounds.width - size, y: yPos))
        path.line(to: CGPoint(x: bounds.width, y: yPos + size))
        path.close()
        Self.deletedColor.setFill()
        path.fill()
    }

    /// Index of the first change whose range ends at or after `line`.
    private func firstIndex(endingAtOrAfter line: Int) -> Int {
        var low = 0
        var high = changes.count
        while low < high {
            let mid = (low + high) / 2
            if changes[mid].lines.upperBound < line {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
