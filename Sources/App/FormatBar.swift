import AppKit

/// Formatting bar shown under the title bar.
///
/// Buttons are laid out left to right in groups; when the window is too narrow, the ones that don't
/// fit are hidden and offered in a "…" (more) menu instead. Pane toggles, Copy and Export
/// stay pinned on the right. Actions are nil-targeted and reach `EditorWindowController` through the
/// responder chain.
final class FormatBar: NSView {
    static let height: CGFloat = 36

    private enum Kind {
        case command(FormatCommand)
        case headingMenu
        case separator
    }

    private struct Entry {
        let kind: Kind
        let view: NSView
        let width: CGFloat
    }

    private static let groups: [[Kind]] = [
        [.headingMenu, .command(.heading1), .command(.heading2), .command(.heading3)],
        [.command(.bold), .command(.italic), .command(.underline), .command(.strikethrough),
         .command(.inlineCode), .command(.codeBlock)],
        [.command(.bulletList), .command(.numberedList), .command(.taskList), .command(.blockquote),
         .command(.outdent), .command(.indent)],
        [.command(.link), .command(.image), .command(.table), .command(.horizontalRule), .command(.comment),
         .command(.superscript), .command(.subscript), .command(.clearFormatting)],
    ]

    private static let buttonSize = NSSize(width: 28, height: 26)
    private static let gap: CGFloat = 2
    private static let separatorWidth: CGFloat = 13
    private static let sideInset: CGFloat = 8

    private var entries: [Entry] = []
    private var trailing: [NSView] = []
    private var overflow: [Entry] = []
    private let moreButton: NSButton
    private let editorButton: NSButton
    private let previewButton: NSButton
    /// The Export button, used to anchor the "export finished" popover.
    private(set) var exportButton: NSButton!
    /// Called when the Editor / Preview toggle buttons are clicked.
    var onTogglePane: ((EditorPane) -> Void)?

    override var isFlipped: Bool { true }

    init() {
        moreButton = Self.makeButton(Icons.symbol("ellipsis", fallback: "…"), tip: "More formatting tools")
        // Plain buttons (no on/off state): the panes themselves show what's visible.
        editorButton = Self.makeButton(Icons.symbol("rectangle.lefthalf.inset.filled", fallback: "E"), tip: "Hide Editor (⌃⌘E)")
        previewButton = Self.makeButton(Icons.symbol("rectangle.righthalf.inset.filled", fallback: "P"), tip: "Hide Preview (⌃⌘P)")
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: Self.height))

        for (gi, group) in Self.groups.enumerated() {
            if gi > 0 { addEntry(.separator) }
            for kind in group { addEntry(kind) }
        }

        moreButton.target = self
        moreButton.action = #selector(showMoreMenu(_:))
        addSubview(moreButton)

        let copy = Self.makeButton(Icons.symbol("doc.on.doc", fallback: "Copy"), tip: "Copy as Markdown, HTML or rich text")
        copy.target = self
        copy.action = #selector(showCopyMenu(_:))
        let export = Self.makeButton(Icons.symbol("square.and.arrow.up", fallback: "Export"),
                                     tip: "Export as HTML, PDF, ODT, DOCX or RTF")
        export.target = self
        export.action = #selector(showExportMenu(_:))
        exportButton = export

        editorButton.target = self
        editorButton.action = #selector(toggleEditor)
        previewButton.target = self
        previewButton.action = #selector(togglePreview)

        trailing = [editorButton, previewButton, copy, export]
        trailing.forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Building

    private static func symbolSized(_ image: NSImage) -> NSImage {
        image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)) ?? image
    }

    /// Toolbar button icon: visually centred on a fixed canvas so every icon shares one optical centre line.
    private static func sized(_ image: NSImage) -> NSImage {
        Icons.normalized(symbolSized(image), canvas: NSSize(width: 22, height: 18), box: NSSize(width: 19, height: 15))
    }


    private static func makeButton(_ image: NSImage, tip: String) -> NSButton {
        let b = NSButton(image: sized(image), target: nil, action: nil)
        b.bezelStyle = .recessed
        b.showsBorderOnlyWhileMouseInside = true
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleProportionallyDown
        b.toolTip = tip
        b.setButtonType(.momentaryPushIn)
        b.frame.size = buttonSize
        return b
    }

    private func addEntry(_ kind: Kind) {
        let view: NSView
        let width: CGFloat
        switch kind {
        case let .command(cmd):
            let b = Self.makeButton(cmd.icon, tip: cmd.toolTip)
            b.action = #selector(EditorWindowController.performFormat(_:))
            b.tag = cmd.rawValue
            view = b
            width = Self.buttonSize.width
        case .headingMenu:
            let b = Self.makeButton(Icons.symbol("textformat.size", fallback: "¶"), tip: "Paragraph style: Normal text, Heading 1–6")
            b.target = self
            b.action = #selector(showHeadingMenu(_:))
            view = b
            width = Self.buttonSize.width
        case .separator:
            let box = NSBox()
            box.boxType = .separator
            view = box
            width = Self.separatorWidth
        }
        addSubview(view)
        entries.append(Entry(kind: kind, view: view, width: width))
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let h = bounds.height

        var right = bounds.width - Self.sideInset
        for v in trailing.reversed() {
            let size = v is NSSegmentedControl ? v.fittingSize : Self.buttonSize
            right -= size.width
            v.frame = NSRect(x: right, y: ((h - size.height) / 2).rounded(), width: size.width, height: size.height)
            right -= 4
        }
        let limit = right - 10

        let total = entries.reduce(Self.sideInset) { $0 + $1.width + Self.gap }
        let available = total <= limit ? limit : limit - Self.buttonSize.width - Self.gap

        var x = Self.sideInset
        var overflowing = false
        overflow = []
        for e in entries {
            if !overflowing && x + e.width <= available {
                e.view.isHidden = false
                let eh = e.view is NSBox ? 18 : Self.buttonSize.height
                let ex = e.view is NSBox ? x + (e.width - 1) / 2 : x
                let ew = e.view is NSBox ? 1 : e.width
                e.view.frame = NSRect(x: ex, y: ((h - eh) / 2).rounded(), width: ew, height: eh)
                x += e.width + Self.gap
            } else {
                overflowing = true
                e.view.isHidden = true
                overflow.append(e)
            }
        }
        // Never end the visible row with a separator.
        if overflowing, let lastVisible = entries.last(where: { !$0.view.isHidden }), case .separator = lastVisible.kind {
            lastVisible.view.isHidden = true
            x -= lastVisible.width + Self.gap
        }

        moreButton.isHidden = overflow.isEmpty
        moreButton.frame = NSRect(x: x, y: ((h - Self.buttonSize.height) / 2).rounded(),
                                  width: Self.buttonSize.width, height: Self.buttonSize.height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            needsLayout = true
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    // MARK: Menus

    private func popUp(_ menu: NSMenu, from button: NSView) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private static func headingItems() -> [NSMenuItem] {
        [FormatCommand.normalText, .heading1, .heading2, .heading3, .heading4, .heading5, .heading6].map { $0.menuItem() }
    }

    @objc private func showHeadingMenu(_ sender: NSButton) {
        let menu = NSMenu()
        Self.headingItems().forEach(menu.addItem)
        popUp(menu, from: sender)
    }

    @objc private func showMoreMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for e in overflow {
            switch e.kind {
            case .separator:
                if let last = menu.items.last, !last.isSeparatorItem { menu.addItem(.separator()) }
            case .headingMenu:
                let item = NSMenuItem(title: "Paragraph Style", action: nil, keyEquivalent: "")
                item.image = Self.menuIcon(Icons.symbol("textformat.size", fallback: "¶"))
                let sub = NSMenu()
                Self.headingItems().forEach(sub.addItem)
                item.submenu = sub
                menu.addItem(item)
            case let .command(cmd):
                let item = cmd.menuItem()
                item.image = Self.menuIcon(cmd.icon)
                menu.addItem(item)
            }
        }
        popUp(menu, from: sender)
    }

    private static func menuIcon(_ image: NSImage) -> NSImage {
        Icons.normalized(symbolSized(image), canvas: NSSize(width: 18, height: 16), box: NSSize(width: 16, height: 14))
    }

    @objc private func showCopyMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(item("Copy Markdown", #selector(EditorWindowController.copyMarkdownDocument(_:)), "c", [.command, .shift]))
        menu.addItem(item("Copy HTML", #selector(EditorWindowController.copyHTML(_:)), "c", [.command, .option]))
        menu.addItem(item("Copy Rich Text", #selector(EditorWindowController.copyRichText(_:)), "c", [.command, .option, .shift]))
        popUp(menu, from: sender)
    }

    @objc private func showExportMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for f in ExportFormat.allCases {
            menu.addItem(item(f.title, EditorWindowController.exportSelector(f), f.shortcut?.key ?? "", f.shortcut?.mods ?? []))
        }
        popUp(menu, from: sender)
    }

    private func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        return i
    }

    // MARK: Panes

    /// Keeps the tooltips describing what a click will do.
    func setPanes(editor: Bool, preview: Bool) {
        editorButton.toolTip = (editor ? "Hide" : "Show") + " Editor (⌃⌘E)"
        previewButton.toolTip = (preview ? "Hide" : "Show") + " Preview (⌃⌘P)"
    }

    @objc private func toggleEditor() { onTogglePane?(.editor) }
    @objc private func togglePreview() { onTogglePane?(.preview) }

    /// Commands currently hidden in the "…" menu (for tests/diagnostics).
    var overflowCount: Int { overflow.filter { if case .separator = $0.kind { return false }; return true }.count }
}
