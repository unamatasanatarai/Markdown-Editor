import AppKit

/// Every formatting command, with its Google Docs–compatible shortcut, menu title and toolbar icon.
/// The raw value is used as the menu item / toolbar item tag.
enum FormatCommand: Int, CaseIterable {
    case bold = 100
    case italic
    case underline
    case strikethrough
    case inlineCode
    case superscript
    case `subscript`
    case heading1
    case heading2
    case heading3
    case heading4
    case heading5
    case heading6
    case normalText
    case bulletList
    case numberedList
    case taskList
    case blockquote
    case codeBlock
    case indent
    case outdent
    case link
    case image
    case table
    case horizontalRule
    case comment
    case newParagraph
    case clearFormatting

    var title: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .inlineCode: return "Inline Code"
        case .superscript: return "Superscript"
        case .subscript: return "Subscript"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .heading4: return "Heading 4"
        case .heading5: return "Heading 5"
        case .heading6: return "Heading 6"
        case .normalText: return "Normal Text"
        case .bulletList: return "Bulleted List"
        case .numberedList: return "Numbered List"
        case .taskList: return "Checklist"
        case .blockquote: return "Blockquote"
        case .codeBlock: return "Code Block"
        case .indent: return "Increase Indent"
        case .outdent: return "Decrease Indent"
        case .link: return "Insert Link"
        case .image: return "Insert Image"
        case .table: return "Insert Table"
        case .horizontalRule: return "Horizontal Rule"
        case .comment: return "Comment"
        case .newParagraph: return "New Paragraph"
        case .clearFormatting: return "Clear Formatting"
        }
    }

    /// Key equivalent and modifiers (Google Docs on macOS where an equivalent exists).
    var shortcut: (key: String, mods: NSEvent.ModifierFlags)? {
        switch self {
        case .bold: return ("b", [.command])
        case .italic: return ("i", [.command])
        case .underline: return ("u", [.command])
        case .strikethrough: return ("x", [.command, .shift])
        case .inlineCode: return ("e", [.command])
        case .superscript: return (".", [.command])
        case .subscript: return (",", [.command])
        case .heading1: return ("1", [.command, .option])
        case .heading2: return ("2", [.command, .option])
        case .heading3: return ("3", [.command, .option])
        case .heading4: return ("4", [.command, .option])
        case .heading5: return ("5", [.command, .option])
        case .heading6: return ("6", [.command, .option])
        case .normalText: return ("0", [.command, .option])
        case .numberedList: return ("7", [.command, .shift])
        case .bulletList: return ("8", [.command, .shift])
        case .taskList: return ("9", [.command, .shift])
        case .blockquote: return ("b", [.command, .shift])
        case .codeBlock: return ("k", [.command, .option])
        case .indent: return ("]", [.command])
        case .outdent: return ("[", [.command])
        case .link: return ("k", [.command])
        case .image: return ("i", [.command, .shift])
        case .table: return ("t", [.command, .option, .shift])
        case .horizontalRule: return ("-", [.command, .option])
        case .comment: return ("m", [.command, .option])
        case .newParagraph: return ("\r", [.command])
        case .clearFormatting: return ("\\", [.command])
        }
    }

    /// Hardware key codes for shortcuts whose shifted character differs per keyboard layout (⇧⌘7/8/9).
    static let shiftedDigitKeyCodes: [UInt16: FormatCommand] = [26: .numberedList, 28: .bulletList, 25: .taskList]

    var op: FormatOp {
        switch self {
        case .bold: return .wrap(prefix: "**", suffix: "**", placeholder: "bold text")
        case .italic: return .wrap(prefix: "*", suffix: "*", placeholder: "italic text")
        case .underline: return .wrap(prefix: "<ins>", suffix: "</ins>", placeholder: "underlined text")
        case .strikethrough: return .wrap(prefix: "~~", suffix: "~~", placeholder: "strikethrough text")
        case .inlineCode: return .wrap(prefix: "`", suffix: "`", placeholder: "code")
        case .superscript: return .wrap(prefix: "<sup>", suffix: "</sup>", placeholder: "superscript")
        case .subscript: return .wrap(prefix: "<sub>", suffix: "</sub>", placeholder: "subscript")
        case .heading1: return .heading(1)
        case .heading2: return .heading(2)
        case .heading3: return .heading(3)
        case .heading4: return .heading(4)
        case .heading5: return .heading(5)
        case .heading6: return .heading(6)
        case .normalText: return .heading(0)
        case .bulletList: return .bulletList
        case .numberedList: return .numberedList
        case .taskList: return .taskList
        case .blockquote: return .blockquote
        case .codeBlock: return .codeBlock
        case .indent: return .indent
        case .outdent: return .outdent
        case .link: return .link
        case .image: return .image
        case .table: return .table
        case .horizontalRule: return .horizontalRule
        case .comment: return .comment
        case .newParagraph: return .newParagraph
        case .clearFormatting: return .clearFormatting
        }
    }

    var icon: NSImage {
        switch self {
        case .bold: return Icons.symbol("bold", fallback: "B")
        case .italic: return Icons.symbol("italic", fallback: "I")
        case .underline: return Icons.symbol("underline", fallback: "U")
        case .strikethrough: return Icons.symbol("strikethrough", fallback: "S")
        case .inlineCode: return Icons.inlineCode
        case .superscript: return Icons.symbol("textformat.superscript", fallback: "x²")
        case .subscript: return Icons.symbol("textformat.subscript", fallback: "x₂")
        case .heading1: return Icons.text("H1")
        case .heading2: return Icons.text("H2")
        case .heading3: return Icons.text("H3")
        case .heading4: return Icons.text("H4")
        case .heading5: return Icons.text("H5")
        case .heading6: return Icons.text("H6")
        case .normalText: return Icons.symbol("paragraphsign", fallback: "¶")
        case .bulletList: return Icons.symbol("list.bullet", fallback: "•")
        case .numberedList: return Icons.symbol("list.number", fallback: "1.")
        case .taskList: return Icons.symbol("checklist", fallback: "☑")
        case .blockquote: return Icons.symbol("text.quote", fallback: "❝")
        case .codeBlock: return Icons.codeBlock
        case .indent: return Icons.symbol("increase.indent", fallback: "→")
        case .outdent: return Icons.symbol("decrease.indent", fallback: "←")
        case .link: return Icons.symbol("link", fallback: "🔗")
        case .image: return Icons.symbol("photo", fallback: "IMG")
        case .table: return Icons.symbol("tablecells", fallback: "TBL")
        case .horizontalRule: return Icons.symbol("minus", fallback: "—")
        case .comment: return Icons.symbol("text.bubble", fallback: "<!>")
        case .newParagraph: return Icons.symbol("return", fallback: "↩")
        case .clearFormatting: return Icons.symbol("eraser", fallback: "Tx")
        }
    }

    var toolTip: String {
        guard let s = shortcut else { return title }
        return "\(title) (\(Self.describe(s.key, s.mods)))"
    }

    static func describe(_ key: String, _ mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        return s + (key == "\r" ? "↩" : key.uppercased())
    }

    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(EditorWindowController.performFormat(_:)), keyEquivalent: shortcut?.key ?? "")
        item.keyEquivalentModifierMask = shortcut?.mods ?? []
        item.tag = rawValue
        return item
    }
}

enum Icons {
    /// Re-draws `image` centred on a fixed `canvas` by its *visible* pixels (alpha bounding box),
    /// scaled down to fit `box` if needed. SF Symbols sit on a text baseline with per-symbol padding
    /// (e.g. "textformat.size" draws low), so centring by the image frame looks misaligned in a row.
    static func normalized(_ image: NSImage, canvas: NSSize, box: NSSize) -> NSImage {
        let scale: CGFloat = 3
        let src = image.size
        let pw = Int(ceil(src.width * scale)), ph = Int(ceil(src.height * scale))
        guard pw > 0, ph > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        rep.size = src // must be set before creating the context, so drawing happens in points
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(origin: .zero, size: src))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return image }
        var minX = pw, minY = ph, maxX = -1, maxY = -1
        for y in 0..<ph {
            let row = data + y * rep.bytesPerRow
            for x in 0..<pw where row[x * 4 + 3] > 12 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return image }
        // Bitmap rows run top-down; drawing rects are bottom-up, in points.
        let bounds = NSRect(x: CGFloat(minX) / scale, y: CGFloat(ph - 1 - maxY) / scale,
                            width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        let fit = min(1, box.width / bounds.width, box.height / bounds.height)
        let size = NSSize(width: bounds.width * fit, height: bounds.height * fit)
        let out = NSImage(size: canvas, flipped: false) { _ in
            let dest = NSRect(x: ((canvas.width - size.width) / 2).rounded(.toNearestOrEven),
                              y: ((canvas.height - size.height) / 2).rounded(.toNearestOrEven),
                              width: size.width, height: size.height)
            rep.draw(in: dest, from: bounds, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        out.isTemplate = true
        out.accessibilityDescription = image.accessibilityDescription
        return out
    }

    /// Inline code: the Markdown syntax itself, a letter between backticks (`c`). "</>" read as HTML.
    static var inlineCode: NSImage {
        drawn { _ in
            for x in [2.0, 14.0] as [CGFloat] {
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: x, y: 14))
                tick.line(to: NSPoint(x: x + 1.6, y: 10.5))
                tick.lineWidth = 1.6
                tick.lineCapStyle = .round
                tick.stroke()
            }
            let c = NSAttributedString(string: "c", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.black])
            c.draw(at: NSPoint(x: (18 - c.size().width) / 2, y: 1))
        }
    }

    /// Code block: a panel holding indented lines.
    static var codeBlock: NSImage {
        drawn { _ in
            let panel = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 13), xRadius: 2.5, yRadius: 2.5)
            panel.lineWidth = 1.3
            panel.stroke()
            for (y, x0, x1) in [(10.5, 4.5, 10.5), (8, 7, 13.5), (5.5, 4.5, 9)] as [(CGFloat, CGFloat, CGFloat)] {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: x0, y: y))
                line.line(to: NSPoint(x: x1, y: y))
                line.lineWidth = 1.3
                line.lineCapStyle = .round
                line.stroke()
            }
        }
    }

    private static func drawn(_ body: @escaping (NSRect) -> Void) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { r in
            NSColor.black.set()
            body(r)
            return true
        }
        img.isTemplate = true
        return img
    }

    static func symbol(_ name: String, fallback: String) -> NSImage {
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) { return img }
        return text(fallback)
    }

    static func text(_ s: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor.black])
        let sz = attr.size()
        let img = NSImage(size: NSSize(width: ceil(sz.width) + 2, height: 18), flipped: false) { r in
            attr.draw(at: NSPoint(x: 1, y: (r.height - sz.height) / 2))
            return true
        }
        img.isTemplate = true
        return img
    }
}
