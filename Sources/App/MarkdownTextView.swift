import AppKit

/// Plain-text Markdown source editor with list continuation and undoable formatting edits.
final class MarkdownTextView: NSTextView {
    func configure(highlighter: MarkdownHighlighter) {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        smartInsertDeleteEnabled = false
        font = highlighter.baseFont
        typingAttributes = highlighter.baseAttributes
        defaultParagraphStyle = highlighter.baseAttributes[.paragraphStyle] as? NSParagraphStyle
        textContainerInset = NSSize(width: 18, height: 20)
        backgroundColor = EditorColors.background
        insertionPointColor = EditorColors.text
        selectedTextAttributes = [.backgroundColor: EditorColors.selection]
    }

    /// Applies an edit through the text system so it is undoable and marks the document dirty.
    func apply(_ e: TextEdit) {
        breakUndoCoalescing()
        guard shouldChangeText(in: e.range, replacementString: e.replacement) else { return }
        textStorage?.replaceCharacters(in: e.range, with: e.replacement)
        didChangeText()
        setSelectedRange(e.selection)
        scrollRangeToVisible(e.selection)
        breakUndoCoalescing()
    }

    func perform(_ op: FormatOp) {
        if let e = MarkdownFormatter.edit(for: op, in: string as NSString, selection: selectedRange()) {
            apply(e)
        }
    }

    override func insertNewline(_ sender: Any?) {
        if !hasMarkedText(), let e = MarkdownFormatter.continueList(text: string as NSString, selection: selectedRange()) {
            apply(e)
        } else {
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        if MarkdownFormatter.isListLine(string as NSString, selectedRange()) {
            perform(.indent)
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if MarkdownFormatter.isListLine(string as NSString, selectedRange()) {
            perform(.outdent)
        } else {
            super.insertBacktab(sender)
        }
    }
}
