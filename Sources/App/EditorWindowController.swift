import AppKit

/// A document's controller. It owns no window of its own: it is a tab inside a
/// `DocumentWindowController`, and `window` is the hosting window (used for sheets).
final class EditorWindowController: NSWindowController, NSMenuItemValidation {
    let editor = EditorViewController()
    weak var host: DocumentWindowController?

    init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var window: NSWindow? {
        get { host?.window }
        set { }
    }

    override var isWindowLoaded: Bool { true }

    override func showWindow(_ sender: Any?) {
        if host == nil { DocumentWindowController.hostForNewDocument().add(self) }
        host?.select(self)
        host?.showWindow(sender)
    }

    /// NSDocument closes its window controllers when the document closes: detach the tab.
    override func close() {
        host?.remove(self)
    }

    override func setDocumentEdited(_ dirtyFlag: Bool) {
        host?.refresh()
    }

    override func synchronizeWindowTitleWithDocumentName() {
        host?.refresh()
    }

    private var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }
    private var docTitle: String { markdownDocument?.title ?? "Untitled" }
    private var baseURL: URL? { markdownDocument?.fileURL?.deletingLastPathComponent() }

    // MARK: - Actions

    @objc func performFormat(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSToolbarItem)?.tag ?? (sender as? NSControl)?.tag ?? 0
        guard let cmd = FormatCommand(rawValue: tag) else { return }
        editor.perform(cmd)
    }

    @objc func copyMarkdownDocument(_ sender: Any?) {
        Exporter.copyMarkdown(editor.markdown)
        editor.flash("Markdown copied")
    }

    @objc func copyHTML(_ sender: Any?) {
        Exporter.copyHTML(editor.markdown)
        editor.flash("HTML copied")
    }

    @objc func copyRichText(_ sender: Any?) {
        do {
            try Exporter.copyRichText(editor.markdown, title: docTitle, baseURL: baseURL)
            editor.flash("Rich text copied")
        } catch {
            presentErrorSheet(error)
        }
    }

    @objc func exportHTML(_ sender: Any?) { runExport(.html) }
    @objc func exportPDF(_ sender: Any?) { runExport(.pdf) }
    @objc func exportODT(_ sender: Any?) { runExport(.odt) }
    @objc func exportDOCX(_ sender: Any?) { runExport(.docx) }
    @objc func exportRTF(_ sender: Any?) { runExport(.rtf) }

    static func exportSelector(_ f: ExportFormat) -> Selector {
        switch f {
        case .html: return #selector(exportHTML(_:))
        case .pdf: return #selector(exportPDF(_:))
        case .odt: return #selector(exportODT(_:))
        case .docx: return #selector(exportDOCX(_:))
        case .rtf: return #selector(exportRTF(_:))
        }
    }

    private func runExport(_ format: ExportFormat) {
        guard let window = window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(docTitle).\(format.fileExtension)"
        panel.canCreateDirectories = true
        if let dir = baseURL { panel.directoryURL = dir }
        let markdown = editor.markdown
        let title = docTitle
        let base = baseURL
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Exporter.export(markdown: markdown, title: title, baseURL: base, format: format, to: url, window: window) { error in
                if case ExportError.cancelled? = error {
                    self?.editor.flash("Export cancelled")
                } else if let error = error {
                    self?.presentErrorSheet(error)
                } else {
                    self?.editor.flash("Exported \(url.lastPathComponent)")
                    self?.showExportFinished(url)
                }
            }
        }
    }

    @objc func printPreview(_ sender: Any?) {
        let html = HTMLTemplate.standalone(body: Markdown.html(from: editor.markdown), title: docTitle, theme: .light)
        WebPrintJob(html: html, baseURL: baseURL, mode: .printPanel, window: window) { [weak self] error in
            if let error = error { self?.presentErrorSheet(error) }
        }.start()
    }

    private func presentErrorSheet(_ error: Error) {
        if let window = window {
            presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
        } else {
            NSApp.presentError(error)
        }
    }

    private func showExportFinished(_ url: URL) {
        editor.showExportResult(url)
    }

    @objc func toggleFormatBar(_ sender: Any?) {
        editor.isFormatBarHidden.toggle()
    }

    @objc func toggleEditorPane(_ sender: Any?) {
        editor.togglePane(.editor)
    }

    @objc func togglePreviewPane(_ sender: Any?) {
        editor.togglePane(.preview)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleFormatBar(_:)):
            menuItem.title = editor.isFormatBarHidden ? "Show Toolbar" : "Hide Toolbar"
        case #selector(toggleEditorPane(_:)):
            menuItem.title = editor.isPaneVisible(.editor) ? "Hide Editor" : "Show Editor"
        case #selector(togglePreviewPane(_:)):
            menuItem.title = editor.isPaneVisible(.preview) ? "Hide Preview" : "Show Preview"
        default:
            break
        }
        return true
    }
}
