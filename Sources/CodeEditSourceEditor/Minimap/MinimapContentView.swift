//
//  MinimapContentView.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 4/16/25.
//

import AppKit
import CodeEditTextView

/// Displays the real contents of the minimap. The layout manager and selection manager place views and draw into this
/// view.
///
/// Height and position are managed by ``MinimapView``.
public class MinimapContentView: FlippedNSView {
    weak var textView: TextView?
    weak var layoutManager: TextLayoutManager?
    weak var selectionManager: TextSelectionManager?

    /// Breakpoint lines (1-based) to indicate, and the disabled subset.
    var breakpointLines: Set<Int> = [] {
        didSet { if breakpointLines != oldValue { needsDisplay = true } }
    }
    var disabledBreakpointLines: Set<Int> = [] {
        didSet { if disabledBreakpointLines != oldValue { needsDisplay = true } }
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if textView?.isSelectable ?? false {
            selectionManager?.drawSelections(in: dirtyRect)
        }
        drawBreakpoints(dirtyRect)
    }

    /// Draws a small blue marker at the leading edge for each breakpoint line.
    private func drawBreakpoints(_ dirtyRect: NSRect) {
        guard !breakpointLines.isEmpty, let layoutManager else { return }
        let color = NSColor(srgbRed: 0.20, green: 0.50, blue: 0.90, alpha: 1)
        for line in breakpointLines {
            guard let position = layoutManager.textLineForIndex(line - 1) else { continue }
            let rect = CGRect(
                x: 0,
                y: position.yPos,
                width: 3,
                height: max(2, position.height)
            ).pixelAligned
            guard rect.intersects(dirtyRect) else { continue }
            color.withAlphaComponent(disabledBreakpointLines.contains(line) ? 0.35 : 0.95).setFill()
            rect.fill()
        }
    }

    override public func layout() {
        super.layout()
        layoutManager?.layoutLines()
    }
}
