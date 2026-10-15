//
//  SourceEditor.swift
//  CodeEditSourceEditor
//
//  Created by Lukas Pistrol on 24.05.22.
//

import AppKit
import SwiftUI
import CodeEditTextView
import CodeEditLanguages

/// A SwiftUI View that provides source editing functionality.
public struct SourceEditor: NSViewControllerRepresentable {
    enum TextAPI {
        case binding(Binding<String>)
        case storage(NSTextStorage)
    }

    /// Initializes a new source editor
    /// - Parameters:
    ///   - text: The text content
    ///   - language: The language for syntax highlighting
    ///   - configuration: A configuration object, determining appearance, layout, behaviors  and more.
    ///                    See ``SourceEditorConfiguration``.
    ///   - cursorPositions: The cursor's position in the editor, measured in `(lineNum, columnNum)`
    ///   - highlightProviders: A set of classes you provide to perform syntax highlighting. Leave this as `nil` to use
    ///                         the default `TreeSitterClient` highlighter.
    ///   - undoManager: The undo manager for the text view. Defaults to `nil`, which will create a new CEUndoManager
    ///   - coordinators: Any text coordinators for the view to use. See ``TextViewCoordinator`` for more information.
    public init(
        _ text: Binding<String>,
        language: CodeLanguage,
        configuration: SourceEditorConfiguration,
        state: Binding<SourceEditorState>,
        highlightProviders: [any HighlightProviding]? = nil,
        undoManager: CEUndoManager? = nil,
        coordinators: [any TextViewCoordinator] = [],
        completionDelegate: CodeSuggestionDelegate? = nil,
        jumpToDefinitionDelegate: JumpToDefinitionDelegate? = nil,
        hoverDelegate: HoverDelegate? = nil,
        signatureHelpDelegate: SignatureHelpDelegate? = nil,
        codeActionDelegate: CodeActionDelegate? = nil,
        diagnosticsDelegate: DiagnosticsDelegate? = nil,
        symbolsDelegate: SymbolsDelegate? = nil,
        inlayHintDelegate: InlayHintDelegate? = nil,
        foldRangeDelegate: FoldRangeDelegate? = nil,
        documentHighlightDelegate: DocumentHighlightDelegate? = nil,
        breakpointLines: Set<Int> = [],
        onToggleBreakpoint: ((Int) -> Void)? = nil
    ) {
        self.text = .binding(text)
        self.language = language
        self.configuration = configuration
        self._state = state
        self.highlightProviders = highlightProviders
        self.undoManager = undoManager
        self.coordinators = coordinators
        self.completionDelegate = completionDelegate
        self.jumpToDefinitionDelegate = jumpToDefinitionDelegate
        self.hoverDelegate = hoverDelegate
        self.signatureHelpDelegate = signatureHelpDelegate
        self.codeActionDelegate = codeActionDelegate
        self.diagnosticsDelegate = diagnosticsDelegate
        self.symbolsDelegate = symbolsDelegate
        self.inlayHintDelegate = inlayHintDelegate
        self.foldRangeDelegate = foldRangeDelegate
        self.documentHighlightDelegate = documentHighlightDelegate
        self.breakpointLines = breakpointLines
        self.onToggleBreakpoint = onToggleBreakpoint
    }

    /// Initializes a new source editor
    /// - Parameters:
    ///   - text: The text content
    ///   - language: The language for syntax highlighting
    ///   - configuration: A configuration object, determining appearance, layout, behaviors  and more.
    ///                    See ``SourceEditorConfiguration``.
    ///   - cursorPositions: The cursor's position in the editor, measured in `(lineNum, columnNum)`
    ///   - highlightProviders: A set of classes you provide to perform syntax highlighting. Leave this as `nil` to use
    ///                         the default `TreeSitterClient` highlighter.
    ///   - undoManager: The undo manager for the text view. Defaults to `nil`, which will create a new CEUndoManager
    ///   - coordinators: Any text coordinators for the view to use. See ``TextViewCoordinator`` for more information.
    public init(
        _ text: NSTextStorage,
        language: CodeLanguage,
        configuration: SourceEditorConfiguration,
        state: Binding<SourceEditorState>,
        highlightProviders: [any HighlightProviding]? = nil,
        undoManager: CEUndoManager? = nil,
        coordinators: [any TextViewCoordinator] = [],
        completionDelegate: CodeSuggestionDelegate? = nil,
        jumpToDefinitionDelegate: JumpToDefinitionDelegate? = nil,
        hoverDelegate: HoverDelegate? = nil,
        signatureHelpDelegate: SignatureHelpDelegate? = nil,
        codeActionDelegate: CodeActionDelegate? = nil,
        diagnosticsDelegate: DiagnosticsDelegate? = nil,
        symbolsDelegate: SymbolsDelegate? = nil,
        inlayHintDelegate: InlayHintDelegate? = nil,
        foldRangeDelegate: FoldRangeDelegate? = nil,
        documentHighlightDelegate: DocumentHighlightDelegate? = nil,
        breakpointLines: Set<Int> = [],
        onToggleBreakpoint: ((Int) -> Void)? = nil
    ) {
        self.text = .storage(text)
        self.language = language
        self.configuration = configuration
        self._state = state
        self.highlightProviders = highlightProviders
        self.undoManager = undoManager
        self.coordinators = coordinators
        self.completionDelegate = completionDelegate
        self.jumpToDefinitionDelegate = jumpToDefinitionDelegate
        self.hoverDelegate = hoverDelegate
        self.signatureHelpDelegate = signatureHelpDelegate
        self.codeActionDelegate = codeActionDelegate
        self.diagnosticsDelegate = diagnosticsDelegate
        self.symbolsDelegate = symbolsDelegate
        self.inlayHintDelegate = inlayHintDelegate
        self.foldRangeDelegate = foldRangeDelegate
        self.documentHighlightDelegate = documentHighlightDelegate
        self.breakpointLines = breakpointLines
        self.onToggleBreakpoint = onToggleBreakpoint
    }

    var text: TextAPI
    var language: CodeLanguage
    var configuration: SourceEditorConfiguration
    @Binding var state: SourceEditorState
    var highlightProviders: [any HighlightProviding]?
    var undoManager: CEUndoManager?
    var coordinators: [any TextViewCoordinator]
    weak var completionDelegate: CodeSuggestionDelegate?
    weak var jumpToDefinitionDelegate: JumpToDefinitionDelegate?
    weak var hoverDelegate: HoverDelegate?
    weak var signatureHelpDelegate: SignatureHelpDelegate?
    weak var codeActionDelegate: CodeActionDelegate?
    weak var diagnosticsDelegate: DiagnosticsDelegate?
    weak var symbolsDelegate: SymbolsDelegate?
    weak var inlayHintDelegate: InlayHintDelegate?
    weak var foldRangeDelegate: FoldRangeDelegate?
    weak var documentHighlightDelegate: DocumentHighlightDelegate?
    var breakpointLines: Set<Int> = []
    var onToggleBreakpoint: ((Int) -> Void)?

    public typealias NSViewControllerType = TextViewController

    public func makeNSViewController(context: Context) -> TextViewController {
        let controller = TextViewController(
            string: "",
            language: language,
            configuration: configuration,
            cursorPositions: state.cursorPositions ?? [],
            highlightProviders: context.coordinator.highlightProviders,
            undoManager: undoManager,
            coordinators: coordinators,
            completionDelegate: completionDelegate,
            jumpToDefinitionDelegate: jumpToDefinitionDelegate,
            hoverDelegate: hoverDelegate,
            signatureHelpDelegate: signatureHelpDelegate,
            codeActionDelegate: codeActionDelegate,
            diagnosticsDelegate: diagnosticsDelegate,
            symbolsDelegate: symbolsDelegate,
            inlayHintDelegate: inlayHintDelegate,
            foldRangeDelegate: foldRangeDelegate,
            documentHighlightDelegate: documentHighlightDelegate
        )
        switch text {
        case .binding(let binding):
            controller.textView.setText(binding.wrappedValue)
        case .storage(let textStorage):
            controller.textView.setTextStorage(textStorage)
        }
        if controller.textView == nil {
            controller.loadView()
        }
        if !(state.cursorPositions?.isEmpty ?? true) {
            controller.setCursorPositions(state.cursorPositions ?? [])
        }

        controller.breakpointLines = breakpointLines
        controller.onToggleBreakpoint = onToggleBreakpoint
        context.coordinator.setController(controller)
        return controller
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: text, editorState: $state, highlightProviders: highlightProviders)
    }

    public func updateNSViewController(_ controller: TextViewController, context: Context) {
        controller.completionDelegate = completionDelegate
        controller.jumpToDefinitionDelegate = jumpToDefinitionDelegate
        controller.hoverDelegate = hoverDelegate
        controller.signatureHelpDelegate = signatureHelpDelegate
        controller.codeActionDelegate = codeActionDelegate
        controller.diagnosticsDelegate = diagnosticsDelegate
        controller.symbolsDelegate = symbolsDelegate
        controller.inlayHintDelegate = inlayHintDelegate
        controller.foldRangeDelegate = foldRangeDelegate
        controller.documentHighlightDelegate = documentHighlightDelegate
        controller.breakpointLines = breakpointLines
        controller.onToggleBreakpoint = onToggleBreakpoint

        context.coordinator.updateHighlightProviders(highlightProviders)

        // Prevent infinite loop of update notifications
        if context.coordinator.isUpdateFromTextView {
            context.coordinator.isUpdateFromTextView = false
        } else {
            context.coordinator.isUpdatingFromRepresentable = true
            updateControllerWithState(state, controller: controller)
            context.coordinator.isUpdatingFromRepresentable = false
        }

        // Do manual diffing to reduce the amount of reloads.
        // This helps a lot in view performance, as it otherwise gets triggered on each environment change.
        guard !paramsAreEqual(controller: controller, coordinator: context.coordinator) else {
            return
        }

        if controller.language != language {
            controller.language = language
        }
        controller.configuration = configuration
        updateHighlighting(controller, coordinator: context.coordinator)

        controller.reloadUI()
        return
    }

    private func updateControllerWithState(_ state: SourceEditorState, controller: TextViewController) {
        if let cursorPositions = state.cursorPositions, cursorPositions != state.cursorPositions {
            controller.setCursorPositions(cursorPositions)
        }

        let scrollView = controller.scrollView
        if let scrollPosition = state.scrollPosition, scrollPosition != scrollView?.contentView.bounds.origin {
            controller.scrollView.scroll(controller.scrollView.contentView, to: scrollPosition)
            controller.scrollView.reflectScrolledClipView(controller.scrollView.contentView)
            controller.gutterView.needsDisplay = true
            NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: controller.textView)
        }

        if let findText = state.findText, findText != controller.findViewController?.viewModel.findText {
            controller.findViewController?.viewModel.findText = findText
        }

        if let replaceText = state.replaceText, replaceText != controller.findViewController?.viewModel.replaceText {
            controller.findViewController?.viewModel.replaceText = replaceText
        }

        if let findPanelVisible = state.findPanelVisible,
           let findController = controller.findViewController,
           findController.viewModel.isShowingFindPanel != findPanelVisible {
            // Needs to be on the next runloop, not many great ways to do this besides a dispatch...
            DispatchQueue.main.async {
                if findPanelVisible {
                    findController.showFindPanel()
                } else {
                    findController.hideFindPanel()
                }
            }
        }
    }

    private func updateHighlighting(_ controller: TextViewController, coordinator: Coordinator) {
        if !areHighlightProvidersEqual(controller: controller, coordinator: coordinator) {
            controller.setHighlightProviders(coordinator.highlightProviders)
        }
    }

    /// Checks if the controller needs updating.
    /// - Parameter controller: The controller to check.
    /// - Returns: True, if the controller's parameters should be updated.
    func paramsAreEqual(controller: NSViewControllerType, coordinator: Coordinator) -> Bool {
        controller.language.id == language.id &&
        controller.configuration == configuration &&
        areHighlightProvidersEqual(controller: controller, coordinator: coordinator)
    }

    private func areHighlightProvidersEqual(controller: TextViewController, coordinator: Coordinator) -> Bool {
        controller.highlightProviders.map { ObjectIdentifier($0) }
        == coordinator.highlightProviders.map { ObjectIdentifier($0) }
    }
}
