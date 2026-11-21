import AppKit

/// ⌘Q must be pressed twice to quit: the first press shows a hint, a second press within
/// `window` seconds quits. Quitting from the Dock, logout or shutdown is unaffected because those
/// don't go through the Quit menu item.
final class QuitGuard {
    static let shared = QuitGuard()
    let window: TimeInterval = 1.5

    private var firstPress: Date?
    private var hud: NSPanel?
    private var hideWork: DispatchWorkItem?

    /// Returns true when this press should quit.
    func shouldQuit(now: Date = Date()) -> Bool {
        if let first = firstPress, now.timeIntervalSince(first) <= window {
            firstPress = nil
            return true
        }
        firstPress = now
        return false
    }

    func requestQuit() {
        if shouldQuit() {
            hideHUD()
            NSApp.terminate(nil)
        } else {
            showHUD()
        }
    }

    // MARK: Hint overlay

    private func showHUD() {
        let panel = hud ?? makeHUD()
        hud = panel
        let anchor = NSApp.keyWindow ?? NSApp.mainWindow
        let area = anchor?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.invalidateShadow()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideHUD() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + window, execute: work)
    }

    private func hideHUD() {
        guard let panel = hud, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func makeHUD() -> NSPanel {
        let label = NSTextField(labelWithString: "Press ⌘Q again to quit")
        label.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.sizeToFit()

        let size = NSSize(width: label.frame.width + 48, height: label.frame.height + 28)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        // A mask image (not layer.cornerRadius) is what actually clips a visual-effect view; with a
        // layer radius the window still showed a square, bordered background around the rounded shape.
        effect.maskImage = Self.roundedMask(radius: 12)
        label.frame.origin = NSPoint(x: 24, y: 14)
        effect.addSubview(label)
        panel.contentView = effect
        panel.invalidateShadow()
        return panel
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
