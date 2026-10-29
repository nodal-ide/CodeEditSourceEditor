//
//  TextViewController.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 6/25/23.
//

import AppKit
import CodeEditTextView
import CodeEditLanguages
import SwiftUI
import Combine
import TextFormation

/// # TextViewController
/// 
/// A view controller class for managing a source editor. Uses ``CodeEditTextView/TextView`` for input and rendering,
/// tree-sitter for syntax highlighting, and TextFormation for live editing completions.
public class TextViewController: NSViewController {
    // swiftlint:disable:next line_length
    public static let cursorPositionUpdatedNotification: Notification.Name = .init("TextViewController.cursorPositionNotification")
    // swiftlint:disable:next line_length
    public static let scrollPositionDidUpdateNotification: Notification.Name = .init("TextViewController.scrollPositionDidUpdateNotification")

    // MARK: - Views and Child VCs

    weak var findViewController: FindViewController?

    internal(set) public var scrollView: NSScrollView!
    internal(set) public var textView: TextView!
    var gutterView: GutterView!

    /// Line numbers (1-based) that display a breakpoint marker. Setting this updates the gutter.
    public var breakpointLines: Set<Int> = [] {
        didSet {
            guard breakpointLines != oldValue else { return }
            gutterView?.breakpointLines = breakpointLines
            gutterView?.needsDisplay = true
        }
    }

    /// Lines that differ from the last commit, drawn in the gutter's change ribbon. Setting this updates the gutter.
    public var lineChanges: [LineChange] = [] {
        didSet {
            guard lineChanges != oldValue else { return }
            gutterView?.changeRibbon.changes = lineChanges
        }
    }

    /// Breakpoint lines that are disabled (drawn hollow). Setting this updates the gutter.
    public var disabledBreakpointLines: Set<Int> = [] {
        didSet {
            guard disabledBreakpointLines != oldValue else { return }
            gutterView?.disabledBreakpointLines = disabledBreakpointLines
            gutterView?.needsDisplay = true
        }
    }

    /// Called when the user clicks a gutter line number, with the 1-based line number.
    public var onToggleBreakpoint: ((Int) -> Void)?

    /// Builds the breakpoint right-click menu for a line. Setting this updates the gutter.
    public var onBreakpointMenu: ((Int) -> NSMenu?)? {
        didSet { gutterView?.onBreakpointMenu = onBreakpointMenu }
    }

    /// Returns additional items for the editor's right-click menu.
    ///
    /// Items are appended after the default Cut, Copy, and Paste actions. Return an empty array to leave the menu
    /// unchanged. The closure receives the controller and triggering event.
    public var onContextMenuItems: ((TextViewController, NSEvent) -> [NSMenuItem])?

    /// The 1-based line of the current debugger stop to highlight, or `nil`.
    public var debugLine: Int? {
        didSet {
            guard debugLine != oldValue else { return }
            updateDebugLineHighlight()
        }
    }

    private static let debugLineEmphasisID = "debugCurrentLine"

    private func updateDebugLineHighlight() {
        guard let manager = textView?.emphasisManager else { return }
        if let debugLine, let line = textView?.layoutManager.textLineForIndex(debugLine - 1) {
            manager.replaceEmphases(
                [Emphasis(range: line.range, style: .standard, inactive: true)],
                for: Self.debugLineEmphasisID
            )
        } else {
            manager.removeEmphases(for: Self.debugLineEmphasisID)
        }
        manager.updateLayerBackgrounds()
    }

    /// The reformatting guide view
    var reformattingGuideView: ReformattingGuideView!

    /// Middleman between the text view to our invisible characters config, with knowledge of things like the
    ///  /// user's theme and indent option to help correctly draw invisible character placeholders.
    var invisibleCharactersCoordinator: InvisibleCharactersCoordinator

    var _undoManager: CEUndoManager!
    var systemAppearance: NSAppearance.Name?

    var localEventMonitor: Any?
    var isPostingCursorNotification: Bool = false

    /// Scroll position to apply once, after the view has finished its first layout pass.
    /// Set by `SourceEditor.makeNSViewController` before the view appears; consumed and cleared in `viewDidAppear`.
    /// `nil` after the first appearance — live scroll changes flow through the coordinator binding instead.
    var pendingRestorationScrollPosition: CGPoint?

    /// A default `NSParagraphStyle` with a set `lineHeight`
    lazy var paragraphStyle: NSMutableParagraphStyle = generateParagraphStyle()

    var suggestionTriggerModel = SuggestionTriggerCharacterModel()

    // MARK: - Public Variables

    /// Passthrough value for the `textView`s string
    public var text: String {
        get {
            textView.string
        }
        set {
            self.setText(newValue)
        }
    }

    /// The associated `CodeLanguage`
    public var language: CodeLanguage {
        didSet {
            // Setting the same language re-parses the whole document and flashes (attributes are cleared then
            // re-applied). Only react to genuine language changes.
            if language.id != oldValue.id || language.fingerprint != oldValue.fingerprint {
                highlighter?.setLanguage(language: language)
            }
            setUpTextFormation()
        }
    }

    /// The configuration for the editor, when updated will automatically update the controller to reflect the new
    /// configuration.
    public var configuration: SourceEditorConfiguration {
        didSet {
            configuration.didSetOnController(controller: self, oldConfig: oldValue)
        }
    }

    /// The current cursors' positions ordered by the location of the cursor.
    internal(set) public var cursorPositions: [CursorPosition] = []

    /// The provided highlight provider.
    public var highlightProviders: [HighlightProviding]

    /// A delegate object that can respond to requests for completion items, filtering completion items, and triggering
    /// the suggestion window. See ``CodeSuggestionDelegate``.
    /// - Note: The ``TextViewController`` keeps only a `weak` reference to this object. To function properly, ensure a
    ///         strong reference to the delegate is kept *outside* of this variable.
    public weak var completionDelegate: CodeSuggestionDelegate?

    /// A delegate object that responds to requests for jump to definition actions. see ``JumpToDefinitionDelegate``.
    /// - Note: The ``TextViewController`` keeps only a `weak` reference to this object. To function properly, ensure a
    ///         strong reference to the delegate is kept *outside* of this variable.
    public var jumpToDefinitionDelegate: JumpToDefinitionDelegate? {
        get {
            jumpToDefinitionModel.delegate
        }
        set {
            jumpToDefinitionModel.delegate = newValue
        }
    }

    /// A delegate that provides hover tooltips for identifiers. See ``HoverDelegate``.
    /// - Note: The ``TextViewController`` keeps only a `weak` reference to this object. To function properly, ensure a
    ///         strong reference to the delegate is kept *outside* of this variable.
    public weak var hoverDelegate: HoverDelegate? {
        didSet {
            hoverModel.delegate = hoverDelegate
        }
    }

    /// A delegate that provides signature help while typing a call. See ``SignatureHelpDelegate``.
    /// - Note: The ``TextViewController`` keeps only a `weak` reference to this object.
    public weak var signatureHelpDelegate: SignatureHelpDelegate? {
        didSet {
            signatureHelpModel.delegate = signatureHelpDelegate
        }
    }

    /// A delegate that provides code actions (quick fixes). See ``CodeActionDelegate``.
    /// - Note: The ``TextViewController`` keeps only a `weak` reference to this object.
    public weak var codeActionDelegate: CodeActionDelegate? {
        didSet {
            codeActionModel.delegate = codeActionDelegate
        }
    }

    /// A delegate that provides native diagnostics (rendered as underlines). See ``DiagnosticsDelegate``.
    /// - Note: The ``TextViewController`` keeps only a `weak` reference to this object.
    public weak var diagnosticsDelegate: DiagnosticsDelegate? {
        didSet {
            diagnosticsModel.delegate = diagnosticsDelegate
            // Avoid a full recompute when the same delegate is re-assigned (the SwiftUI
            // representable sets delegates on every update).
            if oldValue !== diagnosticsDelegate {
                diagnosticsModel.refresh()
            }
        }
    }

    /// A delegate that provides document symbols for "Go to Symbol". See ``SymbolsDelegate``.
    /// - Note: The ``TextViewController`` keeps only a `weak` reference to this object.
    public weak var symbolsDelegate: SymbolsDelegate? {
        didSet {
            symbolsModel.delegate = symbolsDelegate
        }
    }

    /// A delegate that provides inline inlay hints. See ``InlayHintDelegate``.
    /// - Note: The ``TextViewController`` keeps only a `weak` reference to this object.
    public weak var inlayHintDelegate: InlayHintDelegate? {
        didSet {
            inlayHintModel.delegate = inlayHintDelegate
            if oldValue !== inlayHintDelegate {
                if inlayHintDelegate == nil {
                    inlayHintModel.clear()
                } else {
                    inlayHintModel.invalidate()
                    inlayHintModel.refresh()
                }
            }
        }
    }

    /// A delegate that provides highlights for occurrences of the symbol under the cursor. See
    /// ``DocumentHighlightDelegate``.
    /// - Note: The ``TextViewController`` keeps only a `weak` reference to this object.
    public weak var documentHighlightDelegate: DocumentHighlightDelegate? {
        didSet {
            documentHighlightModel.delegate = documentHighlightDelegate
            if oldValue !== documentHighlightDelegate {
                if documentHighlightDelegate == nil {
                    documentHighlightModel.clear()
                } else {
                    documentHighlightModel.refresh()
                }
            }
        }
    }

    /// A delegate that provides folding ranges (e.g. from a language server). See ``FoldRangeDelegate``.
    /// - Note: The ``TextViewController`` keeps only a `weak` reference to this object.
    public weak var foldRangeDelegate: FoldRangeDelegate? {
        didSet {
            foldRangeModel.delegate = foldRangeDelegate
            if oldValue !== foldRangeDelegate {
                if foldRangeDelegate == nil {
                    foldRangeModel.clear()
                } else {
                    foldRangeModel.refresh()
                }
            }
        }
    }

    // MARK: - Config Helpers

    /// The font to use in the `textView`
    public var font: NSFont { configuration.appearance.font }

    /// The  ``EditorTheme`` used for highlighting.
    public var theme: EditorTheme { configuration.appearance.theme }

    /// The visual width of tab characters in the text view measured in number of spaces.
    public var tabWidth: Int { configuration.appearance.tabWidth }

    /// The behavior to use when the tab key is pressed.
    public var indentOption: IndentOption { configuration.behavior.indentOption }

    /// A multiplier for setting the line height. Defaults to `1.0`
    public var lineHeightMultiple: CGFloat { configuration.appearance.lineHeightMultiple }

    /// Whether lines wrap to the width of the editor
    public var wrapLines: Bool { configuration.appearance.wrapLines }

    /// The editorOverscroll to use for the textView over scroll
    ///
    /// Measured in a percentage of the view's total height, meaning a `0.3` value will result in overscroll
    /// of 1/3 of the view.
    public var editorOverscroll: CGFloat { configuration.layout.editorOverscroll }

    /// Whether the code editor should use the theme background color or be transparent
    public var useThemeBackground: Bool { configuration.appearance.useThemeBackground }

    /// Optional insets to offset the text view and find panel in the scroll view by.
    public var contentInsets: NSEdgeInsets? { configuration.layout.contentInsets }

    /// An additional amount to inset text by. Horizontal values are ignored.
    ///
    /// This value does not affect decorations like the find panel, but affects things that are relative to text, such
    /// as line numbers and of course the text itself.
    public var additionalTextInsets: NSEdgeInsets? { configuration.layout.additionalTextInsets }

    /// Whether or not text view is editable by user
    public var isEditable: Bool { configuration.behavior.isEditable }

    /// Whether or not text view is selectable by user
    public var isSelectable: Bool { configuration.behavior.isSelectable }

    /// A multiplier that determines the amount of space between characters. `1.0` indicates no space,
    /// `2.0` indicates one character of space between other characters.
    public var letterSpacing: Double { configuration.appearance.letterSpacing }

    /// The type of highlight to use when highlighting bracket pairs. Leave as `nil` to disable highlighting.
    public var bracketPairEmphasis: BracketPairEmphasis? { configuration.appearance.bracketPairEmphasis }

    /// The column at which to show the reformatting guide
    public var reformatAtColumn: Int { configuration.behavior.reformatAtColumn }

    /// If true, uses the system cursor on macOS 14 or greater.
    public var useSystemCursor: Bool { configuration.appearance.useSystemCursor }

    /// Toggle the visibility of the gutter view in the editor.
    public var showGutter: Bool { configuration.peripherals.showGutter }

    /// Toggle the visibility of the reformatting guide in the editor.
    public var showReformattingGuide: Bool { configuration.peripherals.showReformattingGuide }

    /// Toggle the visibility of the uncommitted-change ribbon in the gutter.
    public var showChangeRibbon: Bool { configuration.peripherals.showChangeRibbon }

    /// Configuration for drawing invisible characters.
    ///
    /// See ``InvisibleCharactersConfiguration`` for more details.
    public var invisibleCharactersConfiguration: InvisibleCharactersConfiguration {
        configuration.peripherals.invisibleCharactersConfiguration
    }

    /// Indicates characters that the user may not have meant to insert, such as a zero-width space: `(0x200D)` or a
    /// non-standard quote character: `“ (0x201C)`.
    public var warningCharacters: Set<UInt16> { configuration.peripherals.warningCharacters }

    // MARK: - Internal Variables

    var textCoordinators: [WeakCoordinator] = []

    var highlighter: Highlighter?

    /// The tree sitter client managed by the source editor.
    ///
    /// This will be `nil` if another highlighter provider is passed to the source editor.
    internal(set) public var treeSitterClient: TreeSitterClient? {
        didSet {
            jumpToDefinitionModel.treeSitterClient = treeSitterClient
            hoverModel.treeSitterClient = treeSitterClient
        }
    }

    /// Returns the language routing order for a document location.
    /// Falls back to the editor language when no tree-sitter zone index is available.
    public func languageIDs(at location: Int) -> [LanguageID] {
        var seen = Set<LanguageID>()
        return languageContexts(at: location)
            .map(\.languageID)
            .filter { seen.insert($0).inserted }
    }

    /// Returns active injected-zone details, deepest first, followed by the root context.
    public func languageContexts(at location: Int) -> [LanguageZoneContext] {
        let contexts = treeSitterClient?.languageContexts(at: location) ?? []
        return contexts.isEmpty ? [LanguageZoneContext(languageID: language.id)] : contexts
    }

    var foldProvider: LineFoldProvider

    /// Filters used when applying edits..
    var textFilters: [TextFormation.Filter] = []

    var jumpToDefinitionModel: JumpToDefinitionModel

    var hoverModel: HoverModel

    var signatureHelpModel: SignatureHelpModel

    var codeActionModel: CodeActionModel

    var diagnosticsModel: DiagnosticsModel

    var symbolsModel: SymbolsModel

    var inlayHintModel: InlayHintModel

    var foldRangeModel: FoldRangeModel

    var documentHighlightModel: DocumentHighlightModel

    /// The active snippet session (tab stops), if a snippet is being inserted.
    var snippetSession: SnippetSession?

    var cancellables = Set<AnyCancellable>()

    var textViewInsets: HorizontalEdgeInsets {
        // See https://github.com/CodeEditApp/CodeEditTextView/issues/66 for potential trailing insets.
        HorizontalEdgeInsets(
            left: showGutter ? gutterView.frame.width : 0.0,
            right: 0.0
        )
    }

    // MARK: Init

    public init(
        string: String,
        language: CodeLanguage,
        configuration: SourceEditorConfiguration,
        cursorPositions: [CursorPosition],
        highlightProviders: [HighlightProviding]? = nil,
        catalog: LanguageCatalog = .builtIn,
        foldProvider: LineFoldProvider? = nil,
        undoManager: CEUndoManager? = nil,
        coordinators: [TextViewCoordinator] = [],
        completionDelegate: CodeSuggestionDelegate? = nil,
        jumpToDefinitionDelegate: JumpToDefinitionDelegate? = nil,
        hoverDelegate: HoverDelegate? = nil,
        signatureHelpDelegate: SignatureHelpDelegate? = nil,
        codeActionDelegate: CodeActionDelegate? = nil,
        diagnosticsDelegate: DiagnosticsDelegate? = nil,
        symbolsDelegate: SymbolsDelegate? = nil,
        inlayHintDelegate: InlayHintDelegate? = nil,
        foldRangeDelegate: FoldRangeDelegate? = nil,
        documentHighlightDelegate: DocumentHighlightDelegate? = nil
    ) {
        self.language = language
        self.configuration = configuration
        self.cursorPositions = cursorPositions
        let resolvedProviders = highlightProviders ?? [TreeSitterClient(catalog: catalog)]
        self.highlightProviders = resolvedProviders
        self.foldProvider = foldProvider ?? LineIndentationFoldProvider()
        self._undoManager = undoManager
        self.invisibleCharactersCoordinator = InvisibleCharactersCoordinator(configuration: configuration)
        self.completionDelegate = completionDelegate
        self.hoverDelegate = hoverDelegate
        self.signatureHelpDelegate = signatureHelpDelegate
        self.jumpToDefinitionModel = JumpToDefinitionModel(
            controller: nil,
            treeSitterClient: treeSitterClient,
            delegate: jumpToDefinitionDelegate
        )
        self.hoverModel = HoverModel(
            controller: nil,
            treeSitterClient: treeSitterClient,
            delegate: hoverDelegate
        )
        self.signatureHelpModel = SignatureHelpModel(
            controller: nil,
            delegate: signatureHelpDelegate
        )
        self.codeActionModel = CodeActionModel(
            controller: nil,
            delegate: codeActionDelegate
        )
        self.diagnosticsModel = DiagnosticsModel(
            controller: nil,
            delegate: diagnosticsDelegate
        )
        self.symbolsModel = SymbolsModel(
            controller: nil,
            delegate: symbolsDelegate
        )
        self.inlayHintModel = InlayHintModel(
            controller: nil,
            delegate: inlayHintDelegate
        )
        self.foldRangeModel = FoldRangeModel(
            controller: nil,
            delegate: foldRangeDelegate
        )
        self.documentHighlightModel = DocumentHighlightModel(
            controller: nil,
            delegate: documentHighlightDelegate
        )

        super.init(nibName: nil, bundle: nil)

        jumpToDefinitionModel.controller = self
        hoverModel.controller = self
        hoverModel.diagnosticsModel = diagnosticsModel
        signatureHelpModel.controller = self
        codeActionModel.controller = self
        diagnosticsModel.controller = self
        symbolsModel.controller = self
        inlayHintModel.controller = self
        foldRangeModel.controller = self
        documentHighlightModel.controller = self
        suggestionTriggerModel.controller = self

        if let idx = resolvedProviders.firstIndex(where: { $0 is TreeSitterClient }),
           let client = resolvedProviders[idx] as? TreeSitterClient {
            self.treeSitterClient = client
        }

        self.textView = SourceEditorTextView(
            string: string,
            font: font,
            textColor: theme.text.color,
            lineHeightMultiplier: lineHeightMultiple,
            wrapLines: wrapLines,
            isEditable: isEditable,
            isSelectable: isSelectable,
            letterSpacing: letterSpacing,
            useSystemCursor: useSystemCursor,
            delegate: self
        )

        textView.layoutManager.invisibleCharacterDelegate = invisibleCharactersCoordinator
        textView.contextMenuItemsProvider = { [weak self] event in
            guard let self else { return [] }
            return self.onContextMenuItems?(self, event) ?? []
        }

        // Start after `textView` exists so the initial refresh/clear can safely access it.
        documentHighlightModel.start()

        coordinators.forEach {
            $0.prepareCoordinator(controller: self)
        }
        self.textCoordinators = coordinators.map { WeakCoordinator($0) }

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Set the contents of the editor.
    /// - Parameter text: The new contents of the editor.
    public func setText(_ text: String) {
        self.textView.setText(text)
        self.setUpHighlighter()
        self.gutterView.setNeedsDisplay(self.gutterView.frame)
    }

    /// Scrolls to a specified position with robust bounds clamping to prevent scrolling into blank overscroll.
    /// - Parameter position: The desired scroll position.
    public func scrollToPosition(_ position: CGPoint) {
        guard let scrollView, let textView else { return }
        textView.updateFrameIfNeeded()

        let clipView = scrollView.contentView
        let visibleHeight = clipView.bounds.height
        let docHeight = textView.frame.height
        let estimatedDocHeight = textView.layoutManager?.estimatedHeight() ?? 0

        var targetY = position.y
        if docHeight > 0 && visibleHeight > 0 {
            let maxAllowedY = max(0, docHeight - visibleHeight)
            if targetY > maxAllowedY {
                targetY = maxAllowedY
            }
            if targetY < 0 {
                targetY = 0
            }
            if targetY >= estimatedDocHeight && estimatedDocHeight > 0 {
                targetY = max(0, estimatedDocHeight - (visibleHeight * 0.5))
            }
        }

        let clampedPosition = CGPoint(x: max(0, position.x), y: targetY)
        if clipView.bounds.origin != clampedPosition {
            scrollView.scroll(clipView, to: clampedPosition)
            scrollView.reflectScrolledClipView(clipView)
            gutterView?.needsDisplay = true
            NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: textView)
        }
    }

    deinit {
        if let highlighter {
            textView.removeStorageDelegate(highlighter)
        }
        highlighter = nil
        highlightProviders.removeAll()
        textCoordinators.values().forEach {
            $0.destroy()
        }
        textCoordinators.removeAll()
        NotificationCenter.default.removeObserver(self)
        cancellables.forEach { $0.cancel() }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        localEventMonitor = nil
    }
}
