import AppKit

protocol TabBarDelegate: AnyObject {
    func tabBar(_ bar: TabBar, didSelect index: Int)
    func tabBar(_ bar: TabBar, didClose index: Int)
    func tabBarDidRequestNewTab(_ bar: TabBar)
}

/// In-window document tabs (Safari-style). Unlike macOS native window tabs, every tab lives inside a
/// single NSWindow, so tiling window managers (yabai, Amethyst…) only ever see one window.
final class TabBar: NSView {
    struct Item: Equatable {
        var title: String
        var edited: Bool
        var active: Bool
    }

    static let height: CGFloat = 30
    weak var delegate: TabBarDelegate?
    private(set) var items: [Item] = []
    private var tabViews: [TabItemView] = []
    private let addButton: NSButton

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        addButton = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab") ?? NSImage(),
                             target: nil, action: nil)
        super.init(frame: frame)
        addButton.bezelStyle = .recessed
        addButton.showsBorderOnlyWhileMouseInside = true
        addButton.imagePosition = .imageOnly
        addButton.toolTip = "New Tab (⌘T)"
        addButton.target = self
        addButton.action = #selector(addTapped)
        addSubview(addButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(_ newItems: [Item]) {
        guard newItems != items || tabViews.count != newItems.count else { return }
        items = newItems
        while tabViews.count < items.count {
            let v = TabItemView()
            v.onSelect = { [weak self, weak v] in
                guard let self = self, let v = v, let i = self.tabViews.firstIndex(where: { $0 === v }) else { return }
                self.delegate?.tabBar(self, didSelect: i)
            }
            v.onClose = { [weak self, weak v] in
                guard let self = self, let v = v, let i = self.tabViews.firstIndex(where: { $0 === v }) else { return }
                self.delegate?.tabBar(self, didClose: i)
            }
            addSubview(v)
            tabViews.append(v)
        }
        while tabViews.count > items.count {
            tabViews.removeLast().removeFromSuperview()
        }
        for (v, item) in zip(tabViews, items) { v.item = item }
        needsLayout = true
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let addWidth: CGFloat = 30
        let available = bounds.width - addWidth - 8
        let count = CGFloat(max(tabViews.count, 1))
        let width = max(60, min(260, available / count))
        var x: CGFloat = 0
        for v in tabViews {
            v.frame = NSRect(x: x, y: 0, width: width, height: bounds.height - 1)
            x += width
        }
        addButton.frame = NSRect(x: min(x + 4, bounds.width - addWidth - 4), y: (bounds.height - 22) / 2, width: 26, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    @objc private func addTapped() {
        delegate?.tabBarDidRequestNewTab(self)
    }
}

private final class TabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var item = TabBar.Item(title: "", edited: false, active: false) {
        didSet {
            label.stringValue = item.title
            label.font = NSFont.systemFont(ofSize: 12, weight: item.active ? .semibold : .regular)
            label.textColor = item.active ? .labelColor : .secondaryLabelColor
            toolTip = item.title
            updateCloseButton()
            needsDisplay = true
        }
    }

    private let label = NSTextField(labelWithString: "")
    private let closeButton: NSButton
    private var hovering = false

    override var isFlipped: Bool { true }

    init() {
        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab") ?? NSImage(),
                               target: nil, action: nil)
        super.init(frame: .zero)
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center
        label.cell?.usesSingleLineMode = true
        addSubview(label)
        closeButton.bezelStyle = .recessed
        closeButton.showsBorderOnlyWhileMouseInside = true
        closeButton.imagePosition = .imageOnly
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.toolTip = "Close Tab (⌘W)"
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: 6, y: (bounds.height - 18) / 2, width: 18, height: 18)
        label.sizeToFit()
        let lh = label.frame.height
        label.frame = NSRect(x: 28, y: (bounds.height - lh) / 2, width: max(0, bounds.width - 56), height: lh)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateCloseButton()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateCloseButton()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func otherMouseUp(with event: NSEvent) {
        // Middle-click closes, as in browsers.
        if event.buttonNumber == 2 { onClose?() }
    }

    @objc private func closeTapped() {
        onClose?()
    }

    private func updateCloseButton() {
        // The close button doubles as the "edited" dot: a dot when edited and not hovered.
        if item.edited && !hovering {
            closeButton.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Edited")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .regular))
            closeButton.isHidden = false
        } else {
            closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
            closeButton.isHidden = !(hovering || item.active)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        if item.active {
            NSColor.windowBackgroundColor.setFill()
            r.fill()
        } else if hovering {
            NSColor.labelColor.withAlphaComponent(0.05).setFill()
            r.fill()
        }
        NSColor.separatorColor.setFill()
        NSRect(x: r.maxX - 1, y: 6, width: 1, height: r.height - 12).fill()
    }
}
