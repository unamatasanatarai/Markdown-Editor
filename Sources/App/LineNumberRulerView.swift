import AppKit

/// App-wide "Show Line Numbers" setting (off by default).
enum LineNumberSettings {
    static let key = "ShowLineNumbers"
    static let didChange = Notification.Name("ShowLineNumbersDidChange")

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

/// Vim-style line numbers in a dimmed gutter left of the editor. A wrapped line is numbered on its
/// first visual line only; numbers follow `\n` like the status bar's "Ln".
///
/// Line starts are kept in a sorted array that is patched per edit (no full rescan per keystroke),
/// and only the visible lines are drawn, so the cost doesn't grow with document size.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    /// UTF-16 offsets where lines begin; always starts with 0.
    private(set) var lineStarts: [Int] = [0]
    private let font: NSFont
    private let textFont: NSFont
    /// Width of one digit (the font has monospaced digits, so a label's width is digits × this).
    private let digitWidth: CGFloat
    private lazy var labelAttributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: EditorColors.muted.withAlphaComponent(0.6),
    ]
    private static let padding: CGFloat = 8  // left of the widest number
    private static let gap: CGFloat = 4      // between numbers and the text inset

    init(textView: NSTextView, textFont: NSFont) {
        self.textView = textView
        self.textFont = textFont
        font = NSFont.monospacedDigitSystemFont(ofSize: max(9, textFont.pointSize - 2), weight: .regular)
        digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        rebuild()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    var lineCount: Int { lineStarts.count }

    // MARK: Line index

    /// Recomputes all line starts (document replaced).
    func rebuild() {
        guard let s = textView?.string as NSString? else { return }
        lineStarts = [0]
        Self.appendLineStarts(in: s, range: NSRange(location: 0, length: s.length), to: &lineStarts)
        updateThickness()
        needsDisplay = true
    }

    /// Patches the index for one edit: `editedRange` in new coordinates, `delta` = change in length
    /// (as reported by the text storage delegate).
    func textDidEdit(editedRange: NSRange, changeInLength delta: Int) {
        guard let s = textView?.string as NSString? else { return }
        let loc = editedRange.location
        let oldEnd = NSMaxRange(editedRange) - delta
        // Starts created by newlines inside the replaced text [loc, oldEnd) lie in (loc, oldEnd].
        let first = Self.firstIndex(in: lineStarts, greaterThan: loc)
        let afterRemoved = Self.firstIndex(in: lineStarts, greaterThan: oldEnd)
        var tail = Array(lineStarts[afterRemoved...])
        for k in tail.indices { tail[k] += delta }
        lineStarts.removeSubrange(first...)
        Self.appendLineStarts(in: s, range: editedRange, to: &lineStarts)
        lineStarts.append(contentsOf: tail)
        updateThickness()
        needsDisplay = true
    }

    /// Appends `i + 1` for every "\n" at index `i` in `range`.
    static func appendLineStarts(in s: NSString, range: NSRange, to starts: inout [Int]) {
        let chunk = 4096
        var buffer = [unichar](repeating: 0, count: chunk)
        var pos = range.location
        let end = NSMaxRange(range)
        while pos < end {
            let n = min(chunk, end - pos)
            s.getCharacters(&buffer, range: NSRange(location: pos, length: n))
            for k in 0..<n where buffer[k] == 10 { starts.append(pos + k + 1) }
            pos += n
        }
    }

    /// Index of the first element greater than `value` in a sorted array.
    static func firstIndex(in a: [Int], greaterThan value: Int) -> Int {
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] <= value { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: Drawing

    private func updateThickness() {
        let digits = max(3, String(lineStarts.count).count)
        let thickness = ceil(Self.padding + CGFloat(digits) * digitWidth + Self.gap)
        if ruleThickness != thickness {
            ruleThickness = thickness
            scrollView?.tile() // make room: the clip view must start right of the gutter
        }
    }

    override var requiredThickness: CGFloat { ruleThickness }

    override func draw(_ dirtyRect: NSRect) {
        EditorColors.background.setFill()
        dirtyRect.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let s = tv.string as NSString
        let attrs = labelAttributes
        let visible = tv.visibleRect
        let origin = tv.textContainerOrigin
        let right = ruleThickness - Self.gap
        // All editor fonts share one size, so one baseline fits every line (an empty line's newline
        // glyph reports a different location, which put its number too low).
        let baseline = lm.defaultBaselineOffset(for: textFont)

        func draw(_ number: Int, fragmentTop: CGFloat) {
            let label = String(number)
            let width = CGFloat(label.utf8.count) * digitWidth
            let y = convert(NSPoint(x: 0, y: fragmentTop + baseline + origin.y), from: tv).y - font.ascender
            (label as NSString).draw(at: NSPoint(x: right - width, y: y), withAttributes: attrs)
        }

        if s.length > 0 {
            let glyphs = lm.glyphRange(forBoundingRect: visible.offsetBy(dx: -origin.x, dy: -origin.y), in: tc)
            let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            // First line starting at or before the visible text, then every line start inside it.
            var line = max(0, Self.firstIndex(in: lineStarts, greaterThan: chars.location) - 1)
            while line < lineStarts.count, lineStarts[line] < s.length, lineStarts[line] <= NSMaxRange(chars) {
                let g = lm.glyphIndexForCharacter(at: lineStarts[line])
                let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
                draw(line + 1, fragmentTop: frag.minY)
                line += 1
            }
        }
        // Empty last line (empty document or text ending in "\n").
        if lineStarts.last == s.length, !lm.extraLineFragmentRect.isEmpty {
            let frag = lm.extraLineFragmentRect
            draw(lineStarts.count, fragmentTop: frag.minY)
        }
    }
}
