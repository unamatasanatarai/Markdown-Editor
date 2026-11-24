import AppKit

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    private var loadedText = ""
    private var editorController: EditorWindowController? {
        windowControllers.first as? EditorWindowController
    }

    var text: String {
        editorController?.editor.markdown ?? loadedText
    }

    override class var autosavesInPlace: Bool { true }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }

    override func makeWindowControllers() {
        let wc = EditorWindowController()
        addWindowController(wc)
        wc.editor.baseURL = fileURL?.deletingLastPathComponent()
        _ = wc.editor.view
        wc.editor.markdown = loadedText
        if repairedBytes > 0 {
            wc.editor.flash("\(repairedBytes) byte\(repairedBytes == 1 ? "" : "s") weren't valid UTF-8 and were read as "
                + "Windows Latin 1; saving will store them as UTF-8", duration: 10)
        } else if fileURL != nil, fileEncoding != .utf8 {
            wc.editor.flash("Opened as \(TextDecoding.name(fileEncoding))", duration: 6)
        }
        // New documents become a tab in the front window (or a new window for ⌘N).
        DocumentWindowController.hostForNewDocument().add(wc)
    }

    /// Bring the document's tab forward before any "save changes?" prompt (close tab, close window, quit).
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        if let wc = editorController, isDocumentEdited { wc.host?.select(wc) }
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }

    override var fileURL: URL? {
        didSet {
            editorController?.editor.baseURL = fileURL?.deletingLastPathComponent()
        }
    }

    /// Encoding and BOM of the file on disk, so saving writes the file back the way it was read.
    private var fileEncoding: String.Encoding = .utf8
    private var fileHasBOM = false
    private var repairedBytes = 0

    override func data(ofType typeName: String) throws -> Data {
        let out = TextDecoding.encode(text, encoding: fileEncoding, hasBOM: fileHasBOM)
        if out.encoding != fileEncoding {
            // Never change a file's encoding silently: say so where the user is looking.
            let message = "Saved as \(TextDecoding.name(out.encoding)): the text contains characters "
                + "that \(TextDecoding.name(fileEncoding)) cannot store"
            DispatchQueue.main.async { [weak self] in self?.editorController?.editor.flash(message, duration: 8) }
        }
        fileEncoding = out.encoding
        fileHasBOM = out.hasBOM
        return out.data
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = TextDecoding.decode(data)
        loadedText = decoded.text
        fileEncoding = decoded.encoding
        fileHasBOM = decoded.hasBOM
        repairedBytes = decoded.repairedBytes
        // Revert / external change happens on the main thread with the editor already open: refresh it.
        // The initial open reads on a background thread before any window exists (makeWindowControllers
        // then uses loadedText), so nothing is scheduled that could later overwrite the user's typing.
        if Thread.isMainThread, let editor = (windowControllers.first as? EditorWindowController)?.editor {
            editor.markdown = decoded.text
        }
    }

    override func printDocument(_ sender: Any?) {
        editorController?.printPreview(sender)
    }

    var title: String {
        (displayName as NSString).deletingPathExtension
    }
}
