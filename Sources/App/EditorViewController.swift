import AppKit
import WebKit

/// Root view that reports appearance changes (system or manual light/dark switch).
final class AppearanceAwareView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

enum EditorPane { case editor, preview }

/// Split view: Markdown source editor (left) and live GitHub-styled preview (right).
final class EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate, WKNavigationDelegate, NSSplitViewDelegate {
    let highlighter = MarkdownHighlighter()
    private(set) var textView: MarkdownTextView!
    private(set) var webView: WKWebView!
    private var scrollView: NSScrollView!
    private(set) var lineNumbers: LineNumberRulerView!
    private var splitView: PaneSplitView!
    private let formatBar = FormatBar()
    private var formatBarHeight: NSLayoutConstraint!
    private let statsLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")

    var onTextChange: (() -> Void)?
    var baseURL: URL? {
        didSet {
            if isViewLoaded, oldValue?.standardizedFileURL != baseURL?.standardizedFileURL { reloadPreviewShell() }
        }
    }

    private var previewReady = false
    private var renderInFlight = false
    private var renderDirty = false
    private var pendingRender: DispatchWorkItem?
    private var pendingStats: DispatchWorkItem?
    /// Character edits since the last highlight (range in current coordinates, edit count).
    private var pendingEdit: NSRange?
    private var pendingEditCount = 0
    private var messageTimer: Timer?
    private var initialSplitApplied = false
    /// Whether a divider position was saved before this split view existed. Must be read before
    /// `autosaveName` is set: the split view writes its frames on its very first layout.
    private var hadSavedSplit = false
    /// Divider position to restore when a hidden pane is shown again.
    private var lastDividerPosition: CGFloat?
    private static let renderQueue = DispatchQueue(label: "markdown.render", qos: .userInitiated)

    var markdown: String {
        get { textView.string }
        set {
            textView.string = newValue
            pendingEdit = nil
            pendingEditCount = 0
            highlighter.highlightProgressively(textView.textStorage!)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.undoManager?.removeAllActions()
            updateStats()
            schedulePreview(immediate: true)
        }
    }

    override func loadView() {
        let root = AppearanceAwareView(frame: NSRect(x: 0, y: 0, width: 1200, height: 780))
        root.onAppearanceChange = { [weak self] in self?.appearanceChanged() }

        // Editor
        // Text view and scroll view must start with matching sizes; otherwise width autoresizing
        // keeps the text view wider than the visible area and clips the left edge.
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = EditorColors.background
        let size = scrollView.contentSize
        textView = MarkdownTextView(frame: NSRect(origin: .zero, size: size))
        textView.minSize = NSSize(width: 0, height: size.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.configure(highlighter: highlighter)
        textView.delegate = self
        textView.textStorage?.delegate = self
        scrollView.documentView = textView
        lineNumbers = LineNumberRulerView(textView: textView, textFont: highlighter.baseFont)
        scrollView.verticalRulerView = lineNumbers
        scrollView.hasVerticalRuler = true
        applyLineNumberSetting()
        NotificationCenter.default.addObserver(self, selector: #selector(lineNumberSettingChanged),
                                               name: LineNumberSettings.didChange, object: nil)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(editorScrolled),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        // Preview
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false // page content scripts off; we inject via evaluateJavaScript
        config.defaultWebpagePreferences = prefs
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true

        // Split
        splitView = PaneSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.addArrangedSubview(scrollView)
        splitView.addArrangedSubview(webView)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        hadSavedSplit = UserDefaults.standard.object(forKey: "NSSplitView Subview Frames EditorPreviewSplit") != nil
        splitView.autosaveName = "EditorPreviewSplit"
        splitView.translatesAutoresizingMaskIntoConstraints = false

        // Status bar
        let status = NSView()
        status.translatesAutoresizingMaskIntoConstraints = false
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        for l in [statsLabel, messageLabel] {
            l.font = NSFont.systemFont(ofSize: 11)
            l.textColor = .secondaryLabelColor
            l.translatesAutoresizingMaskIntoConstraints = false
            l.lineBreakMode = .byTruncatingTail
            status.addSubview(l)
        }
        messageLabel.alignment = .right
        status.addSubview(sep)

        formatBar.translatesAutoresizingMaskIntoConstraints = false
        formatBar.onTogglePane = { [weak self] pane in self?.togglePane(pane) }
        root.addSubview(formatBar)
        root.addSubview(splitView)
        root.addSubview(status)
        formatBarHeight = formatBar.heightAnchor.constraint(equalToConstant: FormatBar.height)
        NSLayoutConstraint.activate([
            formatBar.topAnchor.constraint(equalTo: root.topAnchor),
            formatBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            formatBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            formatBarHeight,
            splitView.topAnchor.constraint(equalTo: formatBar.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            status.heightAnchor.constraint(equalToConstant: 22),
            sep.topAnchor.constraint(equalTo: status.topAnchor),
            sep.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: status.trailingAnchor),
            statsLabel.leadingAnchor.constraint(equalTo: status.leadingAnchor, constant: 12),
            statsLabel.centerYAnchor.constraint(equalTo: status.centerYAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: status.trailingAnchor, constant: -12),
            messageLabel.centerYAnchor.constraint(equalTo: status.centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: statsLabel.trailingAnchor, constant: 12),
        ])
        view = root
        applyFormatBarVisibility()
        reloadPreviewShell()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // First layout with a real width (also for tabs that are never "shown" on their own):
        // default to 50/50 unless the user already has a saved divider position.
        if !initialSplitApplied, splitView.bounds.width > 0 {
            initialSplitApplied = true
            if !hadSavedSplit {
                splitView.setPosition(splitView.bounds.width / 2, ofDividerAt: 0)
            }
            formatBar.setPanes(editor: isPaneVisible(.editor), preview: isPaneVisible(.preview))
        }
        // The line-number gutter is implemented by AppKit as a left content inset of the clip view:
        // the text view gets the remaining width and the "unscrolled" x origin is -inset.
        let insets = scrollView.contentView.contentInsets
        let width = scrollView.contentSize.width - insets.left - insets.right
        if abs(textView.frame.width - width) > 0.5 {
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
            if scrollView.rulersVisible { lineNumbers.needsDisplay = true } // lines re-wrapped
        }
        if scrollView.contentView.bounds.origin.x != -insets.left {
            scrollView.contentView.scroll(to: NSPoint(x: -insets.left, y: scrollView.contentView.bounds.origin.y))
        }
        renderIfStaleAndVisible()
    }

    // MARK: Format bar

    var isFormatBarHidden: Bool {
        get { UserDefaults.standard.bool(forKey: "FormatBarHidden") }
        set {
            UserDefaults.standard.set(newValue, forKey: "FormatBarHidden")
            applyFormatBarVisibility()
        }
    }

    private func applyFormatBarVisibility() {
        formatBar.isHidden = isFormatBarHidden
        formatBarHeight.constant = isFormatBarHidden ? 0 : FormatBar.height
    }

    var formatBarOverflowCount: Int {
        formatBar.layoutSubtreeIfNeeded()
        return formatBar.overflowCount
    }

    // MARK: Split view

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, 220)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, splitView.bounds.width - 220)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { true }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        if isPaneVisible(.editor) && isPaneVisible(.preview) && scrollView.frame.width > 0 {
            lastDividerPosition = scrollView.frame.width
        }
        formatBar.setPanes(editor: isPaneVisible(.editor), preview: isPaneVisible(.preview))
        renderIfStaleAndVisible()
    }

    // MARK: Panes

    private func paneView(_ pane: EditorPane) -> NSView { pane == .editor ? scrollView : webView }

    var debugPaneFrames: String {
        "applied=\(initialSplitApplied) hadSaved=\(hadSavedSplit) split=\(splitView.frame) editor=\(scrollView.frame) hidden=\(scrollView.isHidden) preview=\(webView.frame) hidden=\(webView.isHidden)"
    }

    func isPaneVisible(_ pane: EditorPane) -> Bool {
        let v = paneView(pane)
        return !v.isHidden && !splitView.isSubviewCollapsed(v) && v.frame.width > 1
    }

    /// Shows or hides a pane. Hiding the only visible pane shows the other one instead, so the
    /// window can never end up empty; showing restores the previous divider position.
    func togglePane(_ pane: EditorPane) {
        let other: EditorPane = pane == .editor ? .preview : .editor
        if isPaneVisible(pane) {
            if !isPaneVisible(other) {
                showPane(other)
            }
            if isPaneVisible(.editor) && isPaneVisible(.preview) { lastDividerPosition = scrollView.frame.width }
            paneView(pane).isHidden = true
            splitView.adjustSubviews()
            // Hiding a pane doesn't move NSSplitView's divider layer, which would stay drawn at the old
            // position over the remaining pane. Moving the divider to the edge explicitly updates it.
            splitView.setPosition(pane == .editor ? 0 : splitView.bounds.width, ofDividerAt: 0)
        } else {
            showPane(pane)
        }
        if !isPaneVisible(.editor) { view.window?.makeFirstResponder(webView) } else { view.window?.makeFirstResponder(textView) }
        formatBar.setPanes(editor: isPaneVisible(.editor), preview: isPaneVisible(.preview))
        if isPaneVisible(.preview) { schedulePreview(immediate: true) }
    }

    private func showPane(_ pane: EditorPane) {
        let v = paneView(pane)
        v.isHidden = false
        splitView.adjustSubviews()
        let width = splitView.bounds.width
        let otherVisible = isPaneVisible(pane == .editor ? .preview : .editor)
        guard width > 0 else { return }
        if otherVisible || splitView.isSubviewCollapsed(v) || v.frame.width <= 1 {
            let pos = min(max(lastDividerPosition ?? width / 2, 220), width - 220)
            splitView.setPosition(pos, ofDividerAt: 0)
        }
    }

    // MARK: Text changes

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        if scrollView.rulersVisible { lineNumbers.textDidEdit(editedRange: editedRange, changeInLength: delta) }
        highlighter.noteEdit(location: editedRange.location, changeInLength: delta)
        pendingEdit = pendingEdit.map { NSUnionRange($0, editedRange) } ?? editedRange
        pendingEditCount += 1
    }

    func textDidChange(_ notification: Notification) {
        if !textView.hasMarkedText() {
            // Single edit: re-highlight just the touched lines. Several edits at once: everything.
            highlighter.highlight(textView.textStorage!, edited: pendingEditCount == 1 ? pendingEdit : nil)
            pendingEdit = nil
            pendingEditCount = 0
        }
        textView.typingAttributes = highlighter.baseAttributes
        scheduleStats()
        schedulePreview(immediate: false)
        onTextChange?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        scheduleStats()
    }

    /// Stats scan the whole document, so they are coalesced instead of running on every keystroke.
    private func scheduleStats() {
        pendingStats?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateStats() }
        pendingStats = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func perform(_ cmd: FormatCommand) {
        view.window?.makeFirstResponder(textView)
        textView.perform(cmd.op)
    }

    private func updateStats() {
        let stats = Self.textStats(textView.string as NSString, selection: textView.selectedRange())
        var text = "\(stats.words) words · \(stats.characters) characters · Ln \(stats.line), Col \(stats.column)"
        if textView.selectedRange().length > 0 { text += " · \(textView.selectedRange().length) selected" }
        statsLabel.stringValue = text
    }

    /// Word/character counts and caret position in one pass over UTF-16 code units (grapheme
    /// counting and splitting the whole string took seconds on multi-MB documents). Characters
    /// are Unicode scalars, which matches user-perceived characters for nearly all text.
    static func textStats(_ s: NSString, selection: NSRange) -> (words: Int, characters: Int, line: Int, column: Int) {
        let len = s.length
        let caret = min(selection.location, len)
        var words = 0, chars = 0, line = 1, lineStart = 0
        var inWord = false
        let chunk = 4096
        var buffer = [unichar](repeating: 0, count: chunk)
        var pos = 0
        while pos < len {
            let n = min(chunk, len - pos)
            s.getCharacters(&buffer, range: NSRange(location: pos, length: n))
            for k in 0..<n {
                let u = buffer[k]
                if u < 0xDC00 || u > 0xDFFF { chars += 1 } // count a surrogate pair once
                let space = u == 32 || (u >= 9 && u <= 13) || u == 0xA0 || u == 0x2028 || u == 0x2029
                    || u == 0x3000 || u == 0x1680 || (u >= 0x2000 && u <= 0x200A) || u == 0x202F || u == 0x205F || u == 0x85
                if space { inWord = false } else if !inWord { inWord = true; words += 1 }
                let i = pos + k
                if u == 10, i < caret { line += 1; lineStart = i + 1 }
            }
            pos += n
        }
        return (words, chars, line, caret - lineStart + 1)
    }

    /// Shows the export result popover under the Export button (or the status bar if the toolbar is hidden).
    func showExportResult(_ url: URL) {
        let anchor: NSView = !isFormatBarHidden && formatBar.exportButton.window != nil ? formatBar.exportButton : messageLabel
        ExportResultPopover.show(for: url, relativeTo: anchor)
    }

    func flash(_ message: String, duration: TimeInterval = 2.5) {
        messageLabel.stringValue = message
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.messageLabel.stringValue = ""
        }
    }

    // MARK: Preview

    private var isDark: Bool { view.effectiveAppearance.isDark }

    /// Fragments the preview DOM currently shows, each preceded by a `<!--b-->` marker; nil when
    /// unknown or not splice-safe, in which case the next update replaces everything (PERF-002).
    private var shownFragments: [String]?
    /// Version stamped on `#content` by the last update; a splice only applies on top of the
    /// version it was computed against, so a failed or reordered update can't corrupt the DOM.
    private var shownVersion = 0
    private var nextVersion = 0
    /// Incremented on every shell (re)load; updates prepared for an older shell are dropped.
    private var shellGeneration = 0
    /// Text changed while the preview was hidden; render as soon as it is visible again (PERF-003).
    private var previewStale = false
    private var scrollSyncInFlight = false
    private var scrollSyncPending = false
    /// Scroll-sync scripts sent so far (test hook for PERF-004).
    private(set) var scrollSyncScriptsSent = 0
    /// Renders started and preview scripts not yet completed (used by tests to wait for the preview).
    private(set) var renderCount = 0
    private var outstandingPreviewScripts = 0
    var isPreviewSettled: Bool { !renderInFlight && !renderDirty && outstandingPreviewScripts == 0 }

    private var previewShellURL: URL?

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let url = previewShellURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func reloadPreviewShell() {
        guard webView != nil else { return }
        previewReady = false
        shownFragments = nil
        shellGeneration += 1
        scrollSyncInFlight = false
        scrollSyncPending = false

        let baseTag: String? = baseURL.map { base in
            base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        }
        let shellHTML = HTMLTemplate.previewShell(dark: isDark, baseHref: baseTag)
        let tempDir = FileManager.default.temporaryDirectory
        let shellFile = tempDir.appendingPathComponent("markdown_preview_shell_\(ProcessInfo.processInfo.processIdentifier)_\(shellGeneration).html")
        if (try? shellHTML.write(to: shellFile, atomically: true, encoding: .utf8)) != nil {
            if let old = previewShellURL, old != shellFile {
                try? FileManager.default.removeItem(at: old)
            }
            previewShellURL = shellFile
            webView.loadFileURL(shellFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } else {
            webView.loadHTMLString(shellHTML, baseURL: baseURL ?? URL(string: "about:blank"))
        }
    }

    private func appearanceChanged() {
        lineNumbers?.needsDisplay = true
        guard previewReady else { return }
        webView.evaluateJavaScript("document.documentElement.className='\(isDark ? "dark" : "light")'", completionHandler: nil)
    }

    func schedulePreview(immediate: Bool) {
        pendingRender?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.renderPreview() }
        pendingRender = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.12), execute: work)
    }

    /// Renders a stale preview once it becomes visible (pane shown, divider dragged open, first layout).
    private func renderIfStaleAndVisible() {
        if previewStale, previewReady, isPaneVisible(.preview) { schedulePreview(immediate: true) }
    }

    /// At most one render runs at a time; edits made meanwhile trigger exactly one follow-up render
    /// of the latest text, so slow renders can't pile up. Rendering, diffing and building the update
    /// script all happen on the render queue; the main thread only hands the script to WebKit.
    private func renderPreview() {
        guard previewReady else { return }
        guard isPaneVisible(.preview) else {
            previewStale = true
            return
        }
        previewStale = false
        if renderInFlight {
            renderDirty = true
            return
        }
        renderInFlight = true
        renderDirty = false
        renderCount += 1
        let text = textView.string
        let shown = shownFragments
        let base = shownVersion
        nextVersion += 1
        let version = nextVersion
        let generation = shellGeneration
        Self.renderQueue.async {
            let rendered = Markdown.fragments(from: text)
            let update = PreviewUpdate(old: shown, new: rendered.html, selfContained: rendered.selfContained,
                                       base: base, version: version)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.renderInFlight = false
                if self.previewReady, generation == self.shellGeneration { self.apply(update) }
                if self.renderDirty { self.renderPreview() }
            }
        }
    }

    private func apply(_ update: PreviewUpdate) {
        guard let script = update.script else { return } // nothing changed
        shownFragments = update.fragments
        shownVersion = update.version
        let generation = shellGeneration
        outstandingPreviewScripts += 1
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self = self else { return }
            self.outstandingPreviewScripts -= 1
            if update.isSplice, (result as? Bool) != true, generation == self.shellGeneration {
                // The DOM wasn't in the state the splice was computed for: replace it all.
                self.shownFragments = nil
                self.schedulePreview(immediate: true)
            }
            self.syncPreviewScroll()
        }
    }

    /// Test hook: the preview's current `#content` markup.
    func previewContentHTML(_ completion: @escaping (String?) -> Void) {
        webView.evaluateJavaScript("document.getElementById('content').innerHTML") { r, _ in completion(r as? String) }
    }

    /// Test hook: forget the DOM state so the next render replaces the whole preview.
    func forceFullPreviewUpdate() {
        shownFragments = nil
        schedulePreview(immediate: true)
    }

    @objc private func editorScrolled(_ note: Notification) {
        if scrollView.rulersVisible { lineNumbers.needsDisplay = true }
        syncPreviewScroll()
    }

    // MARK: Line numbers

    var showsLineNumbers: Bool { scrollView.rulersVisible }

    @objc private func lineNumberSettingChanged(_ note: Notification) {
        applyLineNumberSetting()
    }

    /// Shows or hides the gutter. While hidden the line index isn't maintained; it is rebuilt on show.
    private func applyLineNumberSetting() {
        let on = LineNumberSettings.isEnabled
        guard on != scrollView.rulersVisible else { return }
        if on { lineNumbers.rebuild() }
        scrollView.rulersVisible = on
        scrollView.tile()
        if isViewLoaded { view.needsLayout = true } // text view width follows the content area; not during loadView
    }

    /// Keeps the preview scrolled proportionally to the editor. At most one script is in flight;
    /// scroll events arriving meanwhile collapse into one follow-up with the latest position
    /// (each round trip takes ~20 ms on a 100 KB document, longer than the event interval — PERF-004).
    private func syncPreviewScroll() {
        guard previewReady, isPaneVisible(.preview) else { return }
        if scrollSyncInFlight {
            scrollSyncPending = true
            return
        }
        let clip = scrollView.contentView
        let maxY = textView.frame.height - clip.bounds.height
        let ratio = maxY > 0 ? min(1, max(0, clip.bounds.origin.y / maxY)) : 0
        let js = "window.scrollTo(0,\(ratio)*(document.documentElement.scrollHeight-window.innerHeight));"
        scrollSyncInFlight = true
        scrollSyncScriptsSent += 1
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self = self else { return }
            self.scrollSyncInFlight = false
            if self.scrollSyncPending {
                self.scrollSyncPending = false
                self.syncPreviewScroll()
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        previewReady = true
        appearanceChanged()
        renderPreview()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            // Once the preview shell has loaded, nothing in the document may navigate any frame
            // (the sanitizer already removes frames, meta refresh and forms; this is the backstop).
            decisionHandler(previewReady ? .cancel : .allow)
            return
        }
        decisionHandler(.cancel)
        if let fragment = url.fragment, !fragment.isEmpty,
           url.scheme == "about" || (url.isFileURL && baseURL.map { url.path == $0.path || url.path == $0.path + "/" } ?? true) {
            let id = fragment.removingPercentEncoding ?? fragment
            guard let data = try? JSONSerialization.data(withJSONObject: [id]),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("var e=document.getElementById(\(json)[0]);if(e)e.scrollIntoView();", completionHandler: nil)
            return
        }
        handleLink(url)
    }

    private func handleLink(_ url: URL) {
        switch LinkPolicy.action(for: url) {
        case let .openExternally(u):
            NSWorkspace.shared.open(u)
        case let .openDocument(u):
            NSDocumentController.shared.openDocument(withContentsOf: u, display: true) { _, _, error in
                if let error = error { NSApp.presentError(error) }
            }
        case let .revealInFinder(u):
            if FileManager.default.fileExists(atPath: u.path) {
                NSWorkspace.shared.activateFileViewerSelecting([u])
            } else {
                NSSound.beep()
                flash("File not found: \(u.lastPathComponent)")
            }
        case let .confirm(u):
            guard let window = view.window else { return }
            let alert = NSAlert()
            alert.messageText = "Open this link?"
            alert.informativeText = "This document links to “\(u.absoluteString)”, which opens in another app."
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { NSWorkspace.shared.open(u) }
            }
        }
    }
}

/// Editor/preview split with a clearly visible divider. The divider takes no space while a pane is
/// hidden, so no line is left at the window edge.
final class PaneSplitView: NSSplitView {
    override var dividerThickness: CGFloat { subviews.contains(where: { $0.isHidden }) ? 0 : 2 }

    override var dividerColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0x6e / 255, green: 0x76 / 255, blue: 0x81 / 255, alpha: 1) // GitHub dark fg-muted grey
                : NSColor(srgbRed: 0xaf / 255, green: 0xb8 / 255, blue: 0xc1 / 255, alpha: 1) // GitHub light neutral grey
        }
    }
}

/// One preview DOM update, computed off the main thread: either a splice that replaces only the
/// fragments between the unchanged prefix and suffix, or a full `innerHTML` replacement.
struct PreviewUpdate {
    /// Script to run in the preview; nil when nothing changed.
    let script: String?
    /// What the DOM shows after a successful update, or nil when it can't be spliced next time.
    let fragments: [String]?
    let isSplice: Bool
    let version: Int

    static let marker = "<!--b-->"

    init(old: [String]?, new: [String], selfContained: Bool, base: Int, version: Int) {
        self.version = version
        guard selfContained else {
            // Raw HTML with unbalanced tags can affect the parse of later blocks: no markers, full replace.
            fragments = nil
            isSplice = false
            script = Self.fullReplace(new.joined(), version: version)
            return
        }
        fragments = new
        guard let old = old else {
            isSplice = false
            script = Self.fullReplace(new.map { Self.marker + $0 }.joined(), version: version)
            return
        }
        var prefix = 0
        let limit = min(old.count, new.count)
        while prefix < limit, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let deleted = old.count - prefix - suffix
        let inserted = new[prefix..<(new.count - suffix)]
        isSplice = true
        if deleted == 0 && inserted.isEmpty {
            script = nil
            return
        }
        let html = Self.jsString(inserted.map { Self.marker + $0 }.joined())
        script = """
        (function(){var c=document.getElementById('content');\
        if(!c||c.getAttribute('data-v')!=='\(base)')return false;\
        var m=[];for(var n=c.firstChild;n;n=n.nextSibling)if(n.nodeType===8&&n.data==='b')m.push(n);\
        if(m.length!==\(old.count))return false;\
        var end=\(prefix + deleted)<m.length?m[\(prefix + deleted)]:null;\
        var x=\(prefix)<m.length?m[\(prefix)]:null;\
        while(x&&x!==end){var nx=x.nextSibling;c.removeChild(x);x=nx;}\
        var h=\(html);if(h){var r=document.createRange();r.selectNodeContents(c);c.insertBefore(r.createContextualFragment(h),end);}\
        c.setAttribute('data-v','\(version)');return true;})()
        """
    }

    private static func fullReplace(_ html: String, version: Int) -> String {
        "(function(){var c=document.getElementById('content');c.innerHTML=\(jsString(html));"
            + "c.setAttribute('data-v','\(version)');return true;})()"
    }

    /// A JavaScript string literal (JSON is a subset of JS).
    static func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let json = String(data: data, encoding: .utf8) else { return "''" }
        return String(json.dropFirst().dropLast())
    }
}
