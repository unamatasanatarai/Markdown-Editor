import AppKit

/// Compact "download finished" popover shown after an export (in the style of a browser's
/// downloads popover): file icon, name, size • Done, and buttons to reveal, open or trash the file.
/// It is transient: clicking anywhere else dismisses it.
final class ExportResultPopover: NSObject, NSPopoverDelegate {
    private static var current: ExportResultPopover?

    private let url: URL
    private let popover = NSPopover()
    private let subtitle = NSTextField(labelWithString: "")
    private var buttons: [NSButton] = []

    static func show(for url: URL, relativeTo anchor: NSView) {
        current?.popover.close()
        let p = ExportResultPopover(url: url)
        current = p
        let edge: NSRectEdge = anchor.isFlipped ? .maxY : .minY // below the anchor
        p.popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: edge)
    }

    private init(url: URL) {
        self.url = url
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let vc = NSViewController()
        vc.view = makeView()
        popover.contentViewController = vc
    }

    private func makeView() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 64))

        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.frame = NSRect(x: 14, y: 14, width: 36, height: 36)

        let name = NSTextField(labelWithString: url.lastPathComponent)
        name.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        name.lineBreakMode = .byTruncatingMiddle
        name.toolTip = url.path
        name.frame = NSRect(x: 60, y: 33, width: 170, height: 18)

        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.stringValue = Self.sizeText(url) + " • Done"
        subtitle.frame = NSRect(x: 60, y: 15, width: 170, height: 16)

        let reveal = button("folder", "Show in Finder", #selector(reveal))
        let open = button("arrow.up.forward.app", "Open", #selector(openFile))
        let trash = button("trash", "Move to Trash", #selector(trashFile))
        for (i, b) in [reveal, open, trash].enumerated() {
            b.frame = NSRect(x: 238 + CGFloat(i) * 38, y: 16, width: 32, height: 32)
        }
        buttons = [reveal, open, trash]
        [icon, name, subtitle, reveal, open, trash].forEach(root.addSubview)
        return root
    }

    private func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) ?? NSImage()
        let b = NSButton(image: image, target: self, action: action)
        b.bezelStyle = .recessed
        b.showsBorderOnlyWhileMouseInside = true
        b.imagePosition = .imageOnly
        b.toolTip = tip
        // No keyboard focus ring: the popover would otherwise outline the first button on open.
        b.focusRingType = .none
        b.refusesFirstResponder = true
        return b
    }

    private static func sizeText(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        popover.close()
    }

    @objc private func openFile() {
        NSWorkspace.shared.open(url)
        popover.close()
    }

    @objc private func trashFile() {
        // Recoverable: the file goes to the Trash, not deleted.
        NSWorkspace.shared.recycle([url]) { [weak self] _, error in
            guard let self = self else { return }
            if let error = error {
                self.subtitle.stringValue = error.localizedDescription
                return
            }
            self.subtitle.stringValue = "Moved to Trash"
            self.buttons.forEach { $0.isEnabled = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.popover.close() }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if Self.current === self { Self.current = nil }
    }
}
