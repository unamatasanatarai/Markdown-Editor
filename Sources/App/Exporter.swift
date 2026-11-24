import AppKit
import UniformTypeIdentifiers
import WebKit

enum ExportFormat: CaseIterable {
    case html, pdf, odt, docx, rtf

    var title: String {
        switch self {
        case .html: return "HTML…"
        case .pdf: return "PDF…"
        case .odt: return "OpenDocument (ODT)…"
        case .docx: return "Word (DOCX)…"
        case .rtf: return "Rich Text (RTF)…"
        }
    }

    var fileExtension: String {
        switch self {
        case .html: return "html"
        case .pdf: return "pdf"
        case .odt: return "odt"
        case .docx: return "docx"
        case .rtf: return "rtf"
        }
    }

    var contentType: UTType {
        switch self {
        case .html: return .html
        case .pdf: return .pdf
        case .rtf: return .rtf
        default: return UTType(filenameExtension: fileExtension) ?? .data
        }
    }

    var shortcut: (key: String, mods: NSEvent.ModifierFlags)? {
        switch self {
        case .html: return ("e", [.command, .option])
        case .pdf: return ("p", [.command, .option])
        case .odt: return ("o", [.command, .option])
        default: return nil
        }
    }

    static func from(extension ext: String) -> ExportFormat? {
        allCases.first { $0.fileExtension == ext.lowercased() } ?? (ext.lowercased() == "htm" ? .html : nil)
    }
}

enum ExportError: LocalizedError {
    case conversionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .conversionFailed(s): return s
        case .cancelled: return "Export cancelled."
        }
    }
}

/// Converts Markdown to the export formats and the clipboard.
enum Exporter {
    /// `window`: when given, long PDF exports show a progress sheet with a Cancel button on it.
    static func export(markdown: String, title: String, baseURL: URL?, format: ExportFormat, to url: URL,
                       window: NSWindow? = nil, completion: @escaping (Error?) -> Void) {
        do {
            switch format {
            case .html:
                let body = Markdown.html(from: markdown)
                try HTMLTemplate.standalone(body: body, title: title, theme: .auto).write(to: url, atomically: true, encoding: .utf8)
                completion(nil)
            case .pdf:
                let html = HTMLTemplate.standalone(body: Markdown.html(from: markdown), title: title, theme: .light)
                WebPrintJob(html: html, baseURL: baseURL, mode: .savePDF(url), window: window, completion: completion).start()
            case .odt, .docx, .rtf:
                let attr = try attributedString(markdown: markdown, title: title, baseURL: baseURL)
                let range = NSRange(location: 0, length: attr.length)
                let data: Data
                switch format {
                case .rtf:
                    data = try attr.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                case .docx:
                    data = try attr.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML, .title: title])
                default:
                    data = try attr.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.openDocument, .title: title])
                }
                try data.write(to: url, options: .atomic)
                completion(nil)
            }
        } catch {
            completion(error)
        }
    }

    /// HTML used for rich text (RTF/DOCX/ODT and the clipboard). Rendered without remote resources:
    /// the HTML importer would fetch them synchronously on the main thread, and paste targets
    /// (e.g. Mail) would fetch them too. Raw HTML is already sanitized by the renderer.
    static func richHTML(markdown: String, title: String) -> String {
        HTMLTemplate.richDocument(body: Markdown.html(from: markdown, allowRemoteResources: false), title: title)
    }

    static func attributedString(markdown: String, title: String, baseURL: URL?) throws -> NSAttributedString {
        try attributedString(richHTML: richHTML(markdown: markdown, title: title), baseURL: baseURL)
    }

    private static func attributedString(richHTML html: String, baseURL: URL?) throws -> NSAttributedString {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
            .timeout: 5.0,
        ]
        if let base = baseURL { options[.baseURL] = base }
        guard let attr = try? NSAttributedString(data: Data(html.utf8), options: options, documentAttributes: nil) else {
            throw ExportError.conversionFailed("Could not convert the document to rich text.")
        }
        return attr
    }

    // MARK: Clipboard

    static func copyMarkdown(_ markdown: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(markdown, forType: .string)
    }

    static func copyHTML(_ markdown: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Markdown.html(from: markdown), forType: .string)
    }

    /// Puts the rendered preview on the clipboard as rich text (HTML + RTF), for pasting into
    /// Google Docs, Word, Pages, Mail, etc.
    static func copyRichText(_ markdown: String, title: String, baseURL: URL?) throws {
        let html = richHTML(markdown: markdown, title: title)
        let attr = try attributedString(richHTML: html, baseURL: baseURL)
        let rtf = try attr.data(from: NSRange(location: 0, length: attr.length),
                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.html, .rtf, .string], owner: nil)
        pb.setString(html, forType: .html) // same sanitized, remote-free HTML as the RTF flavor
        pb.setData(rtf, forType: .rtf)
        pb.setString(attr.string, forType: .string)
    }
}

/// Renders HTML in an off-screen web view and prints it (to a PDF file or via the print panel).
final class WebPrintJob: NSObject, WKNavigationDelegate {
    enum Mode {
        case savePDF(URL)
        case printPanel
    }

    private static var active: Set<WebPrintJob> = []
    private let html: String
    private let baseURL: URL?
    private var printURL: URL?
    private let mode: Mode
    private weak var parentWindow: NSWindow?
    private let completion: (Error?) -> Void
    private var webView: WKWebView!
    private var hostWindow: NSWindow!
    private var printing = false
    private var loaded = false
    private var finished = false
    /// Seconds to wait for subresources (e.g. remote images) before printing what has loaded.
    static let loadTimeout: TimeInterval = 15

    /// Page scripts are disabled: the document's raw HTML must not be able to rewrite the export.
    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs
        return config
    }

    init(html: String, baseURL: URL?, mode: Mode, window: NSWindow?, completion: @escaping (Error?) -> Void) {
        self.html = html
        self.baseURL = baseURL
        self.mode = mode
        parentWindow = window
        self.completion = completion
    }

    func start() {
        Self.active.insert(self)
        let frame = NSRect(x: 0, y: 0, width: 800, height: 1100)
        webView = WKWebView(frame: frame, configuration: Self.makeConfiguration())
        webView.navigationDelegate = self
        hostWindow = NSWindow(contentRect: frame.offsetBy(dx: -10000, dy: -10000), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        hostWindow.isReleasedWhenClosed = false
        hostWindow.contentView = webView
        var loadedViaFileURL = false
        if let base = baseURL {
            let baseStr = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
            let baseTag = "<base href=\"\(MDEscape.attr(baseStr))\">\n"
            var patchedHTML = html
            if let headRange = patchedHTML.range(of: "<head>", options: .caseInsensitive) {
                patchedHTML.insert(contentsOf: baseTag, at: headRange.upperBound)
            }
            let tempDir = FileManager.default.temporaryDirectory
            let printShellFile = tempDir.appendingPathComponent("markdown_print_\(UUID().uuidString).html")
            if (try? patchedHTML.write(to: printShellFile, atomically: true, encoding: .utf8)) != nil {
                printURL = printShellFile
                loadedViaFileURL = true
                webView.loadFileURL(printShellFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
            }
        }
        if !loadedViaFileURL {
            webView.loadHTMLString(html, baseURL: baseURL ?? URL(string: "about:blank"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadTimeout) { [self] in
            guard !printing, !finished else { return }
            loaded = true
            webView.stopLoading()
            beginPrint()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        // Give layout (and images) a moment to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.beginPrint() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only the initial document load; nothing may navigate any frame afterwards.
        decisionHandler(loaded ? .cancel : .allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if !printing { finish(error) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if !printing { finish(error) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(ExportError.conversionFailed("The renderer stopped unexpectedly."))
    }

    private func beginPrint() {
        guard !printing, !finished else { return }
        printing = true
        runPrint()
    }

    private func runPrint() {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.topMargin = 42
        info.bottomMargin = 42
        info.leftMargin = 42
        info.rightMargin = 42
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        if case let .savePDF(url) = mode {
            // Remove an existing file first so a failed print can't be mistaken for success.
            try? FileManager.default.removeItem(at: url)
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        }
        let op = webView.printOperation(with: info)
        if case .savePDF = mode {
            op.showsPrintPanel = false
            // In the app, show progress (with Cancel) so a huge document can't freeze the window silently.
            op.showsProgressPanel = parentWindow != nil
        } else {
            op.showsPrintPanel = true
            op.showsProgressPanel = true
        }
        op.view?.frame = webView.bounds
        op.runModal(for: parentWindow ?? hostWindow, delegate: self,
                    didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if case let .savePDF(url) = mode {
            if !success {
                // NSPrintOperation reports user cancellation and failure the same way; nothing was written.
                try? FileManager.default.removeItem(at: url)
                finish(ExportError.cancelled)
                return
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                finish(ExportError.conversionFailed("PDF export failed."))
                return
            }
        }
        finish(nil)
    }

    private func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true
        if let url = printURL {
            try? FileManager.default.removeItem(at: url)
            printURL = nil
        }
        completion(error)
        hostWindow?.close()
        Self.active.remove(self)
    }
}
