//
//  GutterView.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 8/22/23.
//

import AppKit
import CodeEditTextView
import CodeEditTextViewObjC

public protocol GutterViewDelegate: AnyObject {
    func gutterViewWidthDidUpdate()
}

/// The gutter view displays line numbers that match the text view's line indexes.
/// This view is used as a scroll view's ruler view. It sits on top of the text view so text scrolls underneath the
/// gutter if line wrapping is disabled.
///
/// If the gutter needs more space (when the number of digits in the numbers increases eg. adding a line after line 99),
/// it will notify it's delegate via the ``GutterViewDelegate/gutterViewWidthDidUpdate(newWidth:)`` method. In
/// `SourceEditor`, this notifies the ``TextViewController``, which in turn updates the textview's edge insets
/// to adjust for the new leading inset.
///
/// This view also listens for selection updates, and draws a selected background on selected lines to keep the illusion
/// that the gutter's line numbers are inline with the line itself.
///
/// The gutter view has insets of it's own that are relative to the widest line index. By default, these insets are 20px
/// leading, and 12px trailing. However, this view also has a ``GutterView/backgroundEdgeInsets`` property, that pads
/// the rect that has a background drawn. This allows the text to be scrolled under the gutter view for 8px before being
/// overlapped by the gutter. It should help the textview keep the cursor visible if the user types while the cursor is
/// off the leading edge of the editor.
///
public class GutterView: NSView {
    struct EdgeInsets: Equatable, Hashable {
        let leading: CGFloat
        let trailing: CGFloat

        var horizontal: CGFloat {
            leading + trailing
        }
    }

    @Invalidating(.display)
    var textColor: NSColor = .secondaryLabelColor

    @Invalidating(.display)
    var font: NSFont = .systemFont(ofSize: 13) {
        didSet {
            updateFontLineHeight()
        }
    }

    @Invalidating(.display)
    var edgeInsets: EdgeInsets = EdgeInsets(leading: 20, trailing: 12)

    @Invalidating(.display)
    var backgroundEdgeInsets: EdgeInsets = EdgeInsets(leading: 0, trailing: 8)

    /// The leading padding for the folding ribbon from the line numbers.
    @Invalidating(.display)
    var foldingRibbonPadding: CGFloat = 4

    @Invalidating(.display)
    var backgroundColor: NSColor? = NSColor.controlBackgroundColor

    @Invalidating(.display)
    var highlightSelectedLines: Bool = true

    /// Line numbers (1-based) that display a breakpoint marker.
    @Invalidating(.display)
    var breakpointLines: Set<Int> = []

    /// A subset of ``breakpointLines`` that are disabled (drawn hollow / transparent).
    @Invalidating(.display)
    var disabledBreakpointLines: Set<Int> = []

    /// Called when the user clicks a line number to toggle a breakpoint.
    var onToggleBreakpoint: ((Int) -> Void)?

    /// Builds the context menu for a breakpoint line (right-click). Return `nil` for no menu.
    var onBreakpointMenu: ((Int) -> NSMenu?)?

    @Invalidating(.display)
    var selectedLineTextColor: NSColor? = .labelColor

    @Invalidating(.display)
    var selectedLineColor: NSColor = NSColor.selectedTextBackgroundColor.withSystemEffect(.disabled)

    /// Toggle the visibility of the line fold decoration.
    @Invalidating(.display)
    public var showFoldingRibbon: Bool = true {
        didSet {
            foldingRibbon.isHidden = !showFoldingRibbon
        }
    }

    /// Toggle the visibility of the uncommitted-change ribbon.
    public var showChangeRibbon: Bool = true {
        didSet {
            changeRibbon.isHidden = !showChangeRibbon
            updateWidthIfNeeded()
        }
    }

    private weak var textView: TextView?
    private weak var delegate: GutterViewDelegate?
    private var maxLineNumberWidth: CGFloat = 0
    /// The maximum number of digits found for a line number.
    private var maxLineLength: Int = 0

    private var fontLineHeight = 1.0

    private func updateFontLineHeight() {
        let string = NSAttributedString(string: "0", attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        let ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(0, 1))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)
        fontLineHeight = (ascent + descent + leading)
    }

    /// The view that draws the fold decoration in the gutter.
    var foldingRibbon: LineFoldRibbonView

    /// The view that draws uncommitted changes in the gutter.
    var changeRibbon: ChangeRibbonView

    /// Syntax helper for determining the required space for the folding ribbon.
    private var foldingRibbonWidth: CGFloat {
        if foldingRibbon.isHidden {
            0.0
        } else {
            LineFoldRibbonView.width + foldingRibbonPadding
        }
    }

    /// Space reserved for the change ribbon, to the left of the folding ribbon.
    private var changeRibbonWidth: CGFloat {
        changeRibbon.isHidden ? 0.0 : ChangeRibbonView.contentWidth
    }

    /// The gutter's y positions start at the top of the document and increase as it moves down the screen.
    override public var isFlipped: Bool {
        true
    }

    /// We override this variable so we can update the ``foldingRibbon``'s frame to match the gutter.
    override public var frame: NSRect {
        get {
            super.frame
        }
        set {
            super.frame = newValue
            foldingRibbon.frame = NSRect(
                x: newValue.width - edgeInsets.trailing - foldingRibbonWidth + foldingRibbonPadding,
                y: 0.0,
                width: foldingRibbonWidth,
                height: newValue.height
            )
            changeRibbon.frame = NSRect(
                x: newValue.width - edgeInsets.trailing - foldingRibbonWidth - changeRibbonWidth,
                y: 0.0,
                width: changeRibbonWidth,
                height: newValue.height
            )
        }
    }

    public convenience init(
        configuration: borrowing SourceEditorConfiguration,
        controller: TextViewController,
        delegate: GutterViewDelegate? = nil
    ) {
        self.init(
            font: configuration.appearance.font,
            textColor: configuration.appearance.theme.text.color,
            selectedTextColor: configuration.appearance.theme.selection,
            controller: controller,
            delegate: delegate
        )
    }

    public init(
        font: NSFont,
        textColor: NSColor,
        selectedTextColor: NSColor?,
        controller: TextViewController,
        delegate: GutterViewDelegate? = nil
    ) {
        self.font = font
        self.textColor = textColor
        self.selectedLineTextColor = selectedTextColor ?? .secondaryLabelColor
        self.textView = controller.textView
        self.delegate = delegate

        foldingRibbon = LineFoldRibbonView(controller: controller)
        changeRibbon = ChangeRibbonView(controller: controller)

        super.init(frame: .zero)
        clipsToBounds = true
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        translatesAutoresizingMaskIntoConstraints = false
        layer?.masksToBounds = true

        addSubview(changeRibbon)
        addSubview(foldingRibbon)

        NotificationCenter.default.addObserver(
            forName: TextSelectionManager.selectionChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Updates the width of the gutter if needed to match the maximum line number found as well as the folding ribbon.
    func updateWidthIfNeeded() {
        guard let textView else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        // Reserve at least 3 digits of space no matter what
        let lineStorageDigits = max(3, String(textView.layoutManager.lineCount).count)

        if maxLineLength < lineStorageDigits {
            // Update the max width
            let maxCtLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: String(repeating: "0", count: lineStorageDigits), attributes: attributes)
            )
            let width = CTLineGetTypographicBounds(maxCtLine, nil, nil, nil)
            maxLineNumberWidth = max(maxLineNumberWidth, width)
            maxLineLength = lineStorageDigits
        }

        let newWidth = maxLineNumberWidth + edgeInsets.horizontal + foldingRibbonWidth + changeRibbonWidth
        if frame.size.width != newWidth {
            frame.size.width = newWidth
            delegate?.gutterViewWidthDidUpdate()
        }
    }

    /// Fills the gutter background color.
    /// - Parameters:
    ///   - context: The drawing context to draw in.
    ///   - dirtyRect: A rect to draw in, received from ``draw(_:)``.
    private func drawBackground(_ context: CGContext, dirtyRect: NSRect) {
        guard let backgroundColor else { return }
        let minX = max(backgroundEdgeInsets.leading, dirtyRect.minX)
        let maxX = min(frame.width - backgroundEdgeInsets.trailing - foldingRibbonWidth, dirtyRect.maxX)
        let width = maxX - minX

        context.saveGState()
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(x: minX, y: dirtyRect.minY, width: width, height: dirtyRect.height))
        context.restoreGState()
    }

    /// Draws selected line backgrounds from the text view's selection manager into the gutter view, making the
    /// selection background appear seamless between the gutter and text view.
    /// - Parameter context: The drawing context to use.
    private func drawSelectedLines(_ context: CGContext) {
        guard let textView = textView,
              let selectionManager = textView.selectionManager,
              let visibleRange = textView.visibleTextRange,
              highlightSelectedLines else {
            return
        }
        context.saveGState()

        var highlightedLines: Set<UUID> = []
        context.setFillColor(selectedLineColor.cgColor)

        let xPos = backgroundEdgeInsets.leading
        let width = frame.width - backgroundEdgeInsets.trailing

        for selection in selectionManager.textSelections where selection.range.isEmpty {
            guard let line = textView.layoutManager.textLineForOffset(selection.range.location),
                  visibleRange.intersection(line.range) != nil || selection.range.location == textView.length,
                  !highlightedLines.contains(line.data.id) else {
                continue
            }
            highlightedLines.insert(line.data.id)
            context.fill(
                CGRect(
                    x: xPos,
                    y: line.yPos,
                    width: width,
                    height: line.height
                ).pixelAligned
            )
        }

        context.restoreGState()
    }

    /// Draw line numbers in the gutter, limited to a drawing rect.
    /// - Parameters:
    ///   - context: The drawing context to draw in.
    ///   - dirtyRect: A rect to draw in, received from ``draw(_:)``.
    private func drawLineNumbers(_ context: CGContext, dirtyRect: NSRect) {
        guard let textView = textView else { return }
        var attributes: [NSAttributedString.Key: Any] = [.font: font]

        var selectionRangeMap = IndexSet()
        let textLength = textView.textStorage.length
        textView.selectionManager?.textSelections.forEach { selection in
            let range = selection.range
            // Guard against invalid/overflowing ranges (e.g. a stale or not-found cursor position
            // during a tab switch) — inserting them into an IndexSet traps.
            guard range.location >= 0, range.length >= 0,
                  range.location <= textLength,
                  range.location + range.length <= textLength else { return }
            if range.isEmpty {
                selectionRangeMap.insert(range.location)
            } else {
                selectionRangeMap.insert(range: range)
            }
        }

        context.saveGState()
        context.clip(to: dirtyRect)

        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for linePosition in textView.layoutManager.linesStartingAt(dirtyRect.minY, until: dirtyRect.maxY) {
            if selectionRangeMap.intersects(integersIn: linePosition.range) {
                attributes[.foregroundColor] = selectedLineTextColor ?? textColor
            } else {
                attributes[.foregroundColor] = textColor
            }

            let ctLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: "\(linePosition.index + 1)", attributes: attributes)
            )
            let fragment: LineFragment? = linePosition.data.lineFragments.first?.data
            var ascent: CGFloat = 0
            let lineNumberWidth = CTLineGetTypographicBounds(ctLine, &ascent, nil, nil)
            let fontHeightDifference = ((fragment?.height ?? 0) - fontLineHeight) / 4

            let yPos = linePosition.yPos + ascent + (fragment?.heightDifference ?? 0)/2 + fontHeightDifference
            // Leading padding + (width - linewidth)
            let xPos = edgeInsets.leading + (maxLineNumberWidth - lineNumberWidth)

            ContextSetHiddenSmoothingStyle(context, 16)

            context.textPosition = CGPoint(x: xPos, y: yPos)

            CTLineDraw(ctLine, context)
        }
        context.restoreGState()
    }

    /// Toggles a breakpoint when a line number is clicked (the folding ribbon handles its own clicks).
    override public func mouseDown(with event: NSEvent) {
        guard let textView else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let ribbonX = frame.width - edgeInsets.trailing - foldingRibbonWidth - changeRibbonWidth
        guard point.x < ribbonX,
              let line = textView.layoutManager.textLineForPosition(point.y) else {
            super.mouseDown(with: event)
            return
        }
        onToggleBreakpoint?(line.index + 1)
    }

    /// Shows the breakpoint context menu (or offers to add one) on right-click.
    override public func rightMouseDown(with event: NSEvent) {
        guard let textView else {
            super.rightMouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let ribbonX = frame.width - edgeInsets.trailing - foldingRibbonWidth - changeRibbonWidth
        guard point.x < ribbonX,
              let line = textView.layoutManager.textLineForPosition(point.y),
              let menu = onBreakpointMenu?(line.index + 1) else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// The gutter shows the normal arrow (not the text I-beam) since it isn't editable text.
    override public func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    /// Draws a breakpoint marker in the gutter for each breakpoint line, Xcode-style (blue rounded marker;
    /// disabled breakpoints are drawn hollow).
    private func drawBreakpoints(_ context: CGContext, dirtyRect: NSRect) {
        guard !breakpointLines.isEmpty, let textView else { return }
        let size = CGSize(width: 13, height: 13)
        context.saveGState()
        context.clip(to: dirtyRect)
        for linePosition in textView.layoutManager.linesStartingAt(dirtyRect.minY, until: dirtyRect.maxY) {
            let line = linePosition.index + 1
            guard breakpointLines.contains(line) else { continue }
            let rect = CGRect(
                x: backgroundEdgeInsets.leading + 3,
                y: linePosition.yPos + (linePosition.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            let path = CGPath(roundedRect: rect, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
            if disabledBreakpointLines.contains(line) {
                context.addPath(path)
                context.setStrokeColor(Self.breakpointBlue.withAlphaComponent(0.4).cgColor)
                context.setLineWidth(1.5)
                context.strokePath()
            } else {
                context.saveGState()
                context.addPath(path)
                context.clip()
                let colors = [
                    Self.breakpointBlue.blended(withFraction: 0.28, of: .white)?.cgColor ?? Self.breakpointBlue.cgColor,
                    Self.breakpointBlue.cgColor
                ]
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors as CFArray,
                    locations: [0, 1]
                ) {
                    // The gutter is flipped, so `minY` is the top edge.
                    context.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: rect.midX, y: rect.minY),
                        end: CGPoint(x: rect.midX, y: rect.maxY),
                        options: []
                    )
                }
                context.restoreGState()
            }
        }
        context.restoreGState()
    }

    /// Xcode's breakpoint blue.
    private static let breakpointBlue = NSColor(srgbRed: 0.20, green: 0.50, blue: 0.90, alpha: 1)

    override public func setNeedsDisplay(_ invalidRect: NSRect) {
        updateWidthIfNeeded()
        super.setNeedsDisplay(invalidRect)
    }

    override public func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        context.saveGState()
        drawBackground(context, dirtyRect: dirtyRect)
        drawSelectedLines(context)
        drawLineNumbers(context, dirtyRect: dirtyRect)
        drawBreakpoints(context, dirtyRect: dirtyRect)
        context.restoreGState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        delegate = nil
        textView = nil
    }
}
