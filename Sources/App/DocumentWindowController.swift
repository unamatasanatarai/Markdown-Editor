import AppKit

/// One OS window holding any number of document tabs (see `TabBar`).
///
/// Each document still has its own `EditorWindowController` (NSDocument's window controller), but
/// those controllers don't own windows: they are tabs hosted here. Actions sent through the
/// responder chain are forwarded to the active tab and its document via `supplementalTarget`.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, TabBarDelegate {
    private(set) static var all: [DocumentWindowController] = []
    /// Set while creating a document that should get its own window (⌘N) instead of a tab.
    static var openNextInNewWindow = false

    private(set) var tabs: [EditorWindowController] = []
    private(set) weak var activeTab: EditorWindowController?
    /// Content view controller; editors are its children so they get the normal view-controller
    /// lifecycle (viewDidLayout, viewDidAppear…).
    private let contentController = NSViewController()
    private let tabBar = TabBar(frame: .zero)
    private let container = NSView()
    private var tabBarHeight: NSLayoutConstraint!
    private var closingAll = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 640, height: 400)
        window.tabbingMode = .disallowed // in-window tabs only: no hidden extra NSWindows per tab
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self

        let root = NSView()
        tabBar.delegate = self
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tabBar)
        root.addSubview(container)
        tabBarHeight = tabBar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: root.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabBarHeight,
            container.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        contentController.view = root
        window.contentViewController = contentController
        window.setContentSize(NSSize(width: 1240, height: 800))

        if Self.all.isEmpty {
            window.center()
            windowFrameAutosaveName = "MarkdownEditorWindow"
        } else if let front = Self.front?.window {
            window.setFrame(front.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: front.frame.minX, y: front.frame.maxY)))
        }
        Self.all.append(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The window controller of the frontmost document window, if any.
    static var front: DocumentWindowController? {
        for w in NSApp.orderedWindows {
            if let c = w.windowController as? DocumentWindowController, all.contains(where: { $0 === c }) { return c }
        }
        return all.last
    }

    /// Where a newly created/opened document goes: a tab in the front window, or a new window.
    static func hostForNewDocument() -> DocumentWindowController {
        if !openNextInNewWindow, let front = front { return front }
        return DocumentWindowController()
    }

    // MARK: Tabs

    func add(_ tab: EditorWindowController, select: Bool = true) {
        tab.host = self
        tabs.append(tab)
        if select || activeTab == nil { self.select(tab) } else { refresh() }
    }

    func select(_ tab: EditorWindowController) {
        guard tabs.contains(where: { $0 === tab }) else { return }
        if activeTab !== tab {
            activeTab?.editor.view.removeFromSuperview()
            activeTab = tab
            if tab.editor.parent !== contentController {
                tab.editor.removeFromParent()
                contentController.addChild(tab.editor)
            }
            let v = tab.editor.view
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: container.topAnchor),
                v.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                v.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        refresh()
        window?.makeFirstResponder(tab.editor.textView)
    }

    /// Detaches a tab (its document closed or it moves to another window). Closes the window when empty.
    func remove(_ tab: EditorWindowController) {
        guard let i = tabs.firstIndex(where: { $0 === tab }) else { return }
        tabs.remove(at: i)
        if tab.host === self { tab.host = nil }
        tab.editor.removeFromParent()
        if activeTab === tab {
            tab.editor.view.removeFromSuperview()
            activeTab = nil
            if !tabs.isEmpty { select(tabs[min(i, tabs.count - 1)]) }
        }
        if tabs.isEmpty {
            window?.close()
        } else {
            refresh()
        }
    }

    /// Title, proxy icon, edited dot and tab labels follow the documents.
    func refresh() {
        let docs = tabs.map { $0.document as? NSDocument }
        tabBar.update(zip(tabs, docs).map { tab, doc in
            TabBar.Item(title: doc?.displayName ?? "Untitled", edited: doc?.isDocumentEdited ?? false, active: tab === activeTab)
        })
        tabBarHeight.constant = tabs.count > 1 ? TabBar.height : 0
        tabBar.isHidden = tabs.count < 2
        if let doc = activeTab?.document as? NSDocument, let window = window {
            window.title = doc.displayName
            window.representedURL = doc.fileURL
            window.isDocumentEdited = doc.isDocumentEdited
        }
    }

    // MARK: Tab bar

    func tabBar(_ bar: TabBar, didSelect index: Int) {
        if tabs.indices.contains(index) { select(tabs[index]) }
    }

    func tabBar(_ bar: TabBar, didClose index: Int) {
        if tabs.indices.contains(index) { close(tab: tabs[index]) }
    }

    func tabBarDidRequestNewTab(_ bar: TabBar) {
        window?.makeKeyAndOrderFront(nil)
        NSDocumentController.shared.newDocument(nil)
    }

    // MARK: Closing

    /// Closes one tab, asking to save if needed.
    func close(tab: EditorWindowController, then: ((Bool) -> Void)? = nil) {
        guard let doc = tab.document as? NSDocument else {
            remove(tab)
            then?(true)
            return
        }
        select(tab)
        let ctx = CloseContext(then: then)
        doc.canClose(withDelegate: ctx, shouldClose: #selector(CloseContext.document(_:shouldClose:contextInfo:)), contextInfo: nil)
    }

    /// Closes every tab in turn (stops if the user cancels a save prompt).
    func closeAllTabs(then: ((Bool) -> Void)? = nil) {
        guard let tab = tabs.last else {
            then?(true)
            return
        }
        close(tab: tab) { [weak self] closed in
            guard closed, let self = self else { then?(false); return }
            if self.tabs.isEmpty { then?(true) } else { self.closeAllTabs(then: then) }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if tabs.isEmpty || closingAll { return true }
        closingAll = true
        closeAllTabs { [weak self] _ in self?.closingAll = false }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        Self.all.removeAll { $0 === self }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (activeTab?.document as? NSDocument)?.undoManager
    }

    // MARK: Actions

    @objc func closeTab(_ sender: Any?) {
        if let tab = activeTab { close(tab: tab) } else { window?.performClose(sender) }
    }

    @objc func showNextDocumentTab(_ sender: Any?) { cycle(1) }
    @objc func showPreviousDocumentTab(_ sender: Any?) { cycle(-1) }

    func selectTab(number: Int) {
        guard !tabs.isEmpty else { return }
        // ⌘9 always means the last tab, as in browsers.
        let index = number == 9 ? tabs.count - 1 : number - 1
        if tabs.indices.contains(index) { select(tabs[index]) }
    }

    private func cycle(_ step: Int) {
        guard tabs.count > 1, let tab = activeTab, let i = tabs.firstIndex(where: { $0 === tab }) else { return }
        select(tabs[(i + step + tabs.count) % tabs.count])
    }

    @objc func moveTabToNewWindow(_ sender: Any?) {
        guard tabs.count > 1, let tab = activeTab else { return }
        remove(tab)
        let host = DocumentWindowController()
        host.add(tab)
        host.showWindow(nil)
    }

    @objc func mergeAllWindows(_ sender: Any?) {
        for other in Self.all where other !== self {
            for tab in other.tabs {
                other.remove(tab)
                add(tab, select: false)
            }
        }
        refresh()
        window?.makeKeyAndOrderFront(nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showNextDocumentTab(_:)), #selector(showPreviousDocumentTab(_:)), #selector(moveTabToNewWindow(_:)):
            return tabs.count > 1
        case #selector(mergeAllWindows(_:)):
            return Self.all.count > 1
        default:
            return true
        }
    }

    /// Forward responder-chain actions (format, export, save, print…) to the active tab and its document.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if let tab = activeTab {
            if tab.responds(to: action) { return tab }
            if let doc = tab.document as? NSDocument, doc.responds(to: action) { return doc }
        }
        return super.supplementalTarget(forAction: action, sender: sender)
    }
}

/// Receives NSDocument's `canClose` callback and closes the document if allowed.
private final class CloseContext: NSObject {
    private static var pending: Set<CloseContext> = []
    let then: ((Bool) -> Void)?

    init(then: ((Bool) -> Void)?) {
        self.then = then
        super.init()
        Self.pending.insert(self)
    }

    @objc func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Self.pending.remove(self)
        if shouldClose { document.close() }
        then?(shouldClose)
    }
}
