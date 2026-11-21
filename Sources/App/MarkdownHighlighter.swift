import AppKit

/// GitHub-like editor colours that adapt automatically to light/dark appearance.
enum EditorColors {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { $0.isDark ? hex(dark) : hex(light) }
    }

    static func hex(_ v: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }

    static let background = dynamic(0xFFFFFF, 0x0D1117)
    static let text = dynamic(0x1F2328, 0xE6EDF3)
    static let muted = dynamic(0x6E7781, 0x8B949E)
    static let heading = dynamic(0x0550AE, 0x79C0FF)
    static let code = dynamic(0x0A3069, 0xA5D6FF)
    static let codeBackground = dynamic(0xF6F8FA, 0x161B22)
    static let link = dynamic(0x0969DA, 0x4493F8)
    static let quote = dynamic(0x116329, 0x7EE787)
    static let list = dynamic(0x953800, 0xFFA657)
    static let tag = dynamic(0x116329, 0x7EE787)
    static let selection = dynamic(0xB6D7FF, 0x264F78)
}

/// Lightweight regex-based Markdown syntax highlighting for the source editor.
final class MarkdownHighlighter {
    let baseFont: NSFont
    private let boldFont: NSFont
    private let paragraph: NSParagraphStyle

    init(fontSize: CGFloat = 14) {
        baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        paragraph = p
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: EditorColors.text, .paragraphStyle: paragraph]
    }

    private static func re(_ p: String, _ o: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: o)
    }

    private let heading = re(#"^ {0,3}(#{1,6})(?:[ \t]+.*)?$"#)
    private let setext = re(#"^.+\n {0,3}(=+|-+)[ \t]*$"#)
    // Inline patterns never let a match run past the next opener of the same kind: otherwise every
    // opener on a line without a closer scans to the end of the line, which is O(n²) per line
    // (a 20 KB line froze typing for 30 s per keystroke).
    private let bold = re(#"\*\*(?=\S)(?:[^*\n]|\*(?!\*))+?(?<=\S)\*\*|__(?=\S)(?:[^_\n]|_(?!_))+?(?<=\S)__"#)
    private let italicStar = re(#"(?<![\*\w\\])\*(?![\s\*])([^*\n]+?)(?<![\s\*\\])\*(?![\*\w])"#)
    private let italicUnderscore = re(#"(?<![_\w\\])_(?![\s_])([^_\n]+?)(?<![\s_\\])_(?![_\w])"#)
    private let strike = re(#"~~(?=\S)((?:[^~\n]|~(?!~))+?)(?<=\S)~~"#)
    private let link = re(#"(!?\[)([^\[\]\n]*)(\]\()([^()\[\n]*)(\))"#)
    private let refLink = re(#"(!?\[)([^\[\]\n]+)(\]\[)([^\[\]\n]*)(\])"#)
    private let refDef = re(#"^ {0,3}\[[^\]\n]+\]:.*$"#)
    private let bareURL = re(#"(?<![(<\w])(?:https?://|www\.)[^\s<>()]+[^\s<>().,;:!?'"]"#)
    private let angleLink = re(#"<(?:https?|mailto|ftp):[^<>\s]+>"#)
    private let listMarker = re(#"^[ \t]*(?:>[ \t]*)*([-*+]|\d{1,9}[.)])(?=[ \t])"#)
    private let taskBox = re(#"^[ \t]*(?:>[ \t]*)*(?:[-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\])"#)
    private let quote = re(#"^[ \t]{0,3}(>[ >\t]*)(.*)$"#)
    private let rule = re(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private let htmlTag = re(#"</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>\n]*)?/?>"#)
    private let inlineCode = re(#"(`+)(?!`)(.+?)(?<!`)\1"#)
    private let tablePipe = re(#"^[ \t]*\|.*\|[ \t]*$"#)
    private let footnote = re(#"\[\^[^\[\]\s]+\]"#)

    /// Multi-line constructs found by a linear scan: fenced code blocks and HTML comments.
    struct Structure: Equatable {
        var code: [NSRange] = []
        var comments: [NSRange] = []
        /// Ordered marker kinds; if this changes, block structure may have changed everywhere after it.
        var signature: [UInt16] = []
    }

    private var lastSignature: [UInt16]?

    // MARK: Progressive highlighting (PERF-010)

    /// Size of one progressive highlighting step (UTF-16 units, extended to whole lines).
    static let chunkSize = 65_536
    /// Start of the text not yet highlighted by a progressive pass, or nil when none is running.
    private(set) var progressFrom: Int?
    private var progressGeneration = 0

    /// Highlights the start of a large document synchronously and the rest in chunks on later
    /// main-run-loop turns, so opening a multi-MB file doesn't block the window for the whole pass.
    /// Small documents are highlighted at once.
    func highlightProgressively(_ ts: NSTextStorage) {
        progressGeneration += 1
        progressFrom = nil
        let s = ts.string as NSString
        guard s.length > 2 * Self.chunkSize else {
            highlight(ts)
            return
        }
        let structure = Self.scanStructure(s)
        lastSignature = structure.signature
        let end = NSMaxRange(s.lineRange(for: NSRange(location: Self.chunkSize, length: 0)))
        apply(ts, target: NSRange(location: 0, length: end), structure: structure)
        if end < s.length {
            progressFrom = end
            scheduleNextChunk(ts, generation: progressGeneration)
        }
    }

    private func scheduleNextChunk(_ ts: NSTextStorage, generation: Int) {
        DispatchQueue.main.async { [weak self, weak ts] in
            guard let self = self, let ts = ts, generation == self.progressGeneration, let pending = self.progressFrom else { return }
            let s = ts.string as NSString
            guard pending < s.length else {
                self.progressFrom = nil
                return
            }
            let structure = Self.scanStructure(s)
            guard structure.signature == self.lastSignature else {
                self.highlight(ts) // block structure changed meanwhile: finish with one full pass
                return
            }
            let from = s.lineRange(for: NSRange(location: pending, length: 0)).location
            let end = NSMaxRange(s.lineRange(for: NSRange(location: min(from + Self.chunkSize, s.length - 1), length: 0)))
            self.apply(ts, target: NSRange(location: from, length: end - from), structure: structure)
            self.progressFrom = end < s.length ? end : nil
            if self.progressFrom != nil { self.scheduleNextChunk(ts, generation: generation) }
        }
    }

    /// Keeps a running progressive pass aligned with character edits (from the text storage delegate).
    func noteEdit(location: Int, changeInLength delta: Int) {
        guard let p = progressFrom else { return }
        if location < p { progressFrom = max(location, p + delta) }
    }

    /// Highlights `edited` (expanded to whole lines plus one line of context) when the document's
    /// block structure is unchanged, otherwise the whole document.
    func highlight(_ ts: NSTextStorage, edited: NSRange? = nil) {
        let s = ts.string as NSString
        let structure = Self.scanStructure(s)
        var target = NSRange(location: 0, length: s.length)
        if let e = edited, structure.signature == lastSignature {
            let loc = min(e.location, s.length)
            var r = s.lineRange(for: NSRange(location: loc, length: min(e.length, s.length - loc)))
            if r.location > 0 {
                r = NSUnionRange(r, s.lineRange(for: NSRange(location: r.location - 1, length: 0)))
            }
            if NSMaxRange(r) < s.length {
                r = NSUnionRange(r, s.lineRange(for: NSRange(location: NSMaxRange(r), length: 0)))
            }
            target = r
        }
        lastSignature = structure.signature
        if target.length == s.length { progressFrom = nil } // a full pass completes any progressive one
        apply(ts, target: target, structure: structure)
    }

    /// One pass over a bulk copy of the UTF-16 text. This runs on every keystroke; per-character
    /// `character(at:)` calls and `range(of:)` searches took ~16 ms on a 1 MB document (PERF-008).
    /// Line breaks follow NSString: LF, CR, CRLF, U+0085, U+2028, U+2029.
    static func scanStructure(_ s: NSString) -> Structure {
        var st = Structure()
        let len = s.length
        guard len > 0 else { return st }
        var buffer = [unichar](repeating: 0, count: len)
        s.getCharacters(&buffer, range: NSRange(location: 0, length: len))
        buffer.withUnsafeBufferPointer { b in
            // Fenced code: walk lines, check the first non-space characters.
            var lineStart = 0
            var fenceChar: unichar = 0
            var fenceStart = 0
            while lineStart < len {
                let start = lineStart
                var contentsEnd = start
                while contentsEnd < len {
                    let c = b[contentsEnd]
                    if c == 10 || c == 13 || c == 0x85 || c == 0x2028 || c == 0x2029 { break }
                    contentsEnd += 1
                }
                var end = contentsEnd
                if end < len {
                    end += (b[end] == 13 && end + 1 < len && b[end + 1] == 10) ? 2 : 1
                }
                var i = start
                while i < contentsEnd, b[i] == 32 { i += 1 }
                if i - start < 4, i + 2 < contentsEnd {
                    let c = b[i]
                    if (c == 96 || c == 126), b[i + 1] == c, b[i + 2] == c {
                        if fenceChar == 0 {
                            fenceChar = c
                            fenceStart = start
                            st.signature.append(c)
                        } else if c == fenceChar {
                            var j = i
                            while j < contentsEnd, b[j] == c { j += 1 }
                            while j < contentsEnd, b[j] == 32 || b[j] == 9 { j += 1 }
                            if j == contentsEnd {
                                st.code.append(NSRange(location: fenceStart, length: end - fenceStart))
                                st.signature.append(c)
                                fenceChar = 0
                            }
                        }
                    }
                }
                lineStart = end
            }
            if fenceChar != 0 { st.code.append(NSRange(location: fenceStart, length: len - fenceStart)) }

            // HTML comments: one forward pass ("<!--" … "-->").
            func find(_ pattern: [unichar], from: Int) -> Int? {
                var k = from
                let last = len - pattern.count
                while k <= last {
                    if b[k] == pattern[0] {
                        var m = 1
                        while m < pattern.count, b[k + m] == pattern[m] { m += 1 }
                        if m == pattern.count { return k }
                    }
                    k += 1
                }
                return nil
            }
            let open: [unichar] = [60, 33, 45, 45], close: [unichar] = [45, 45, 62]
            var pos = 0
            while pos < len {
                guard let o = find(open, from: pos) else { break }
                st.signature.append(60)
                let after = o + 4
                let c = find(close, from: after)
                let endPos = c.map { $0 + 3 } ?? len
                if c != nil { st.signature.append(62) }
                st.comments.append(NSRange(location: o, length: endPos - o))
                pos = endPos
            }
        }
        return st
    }

    // MARK: Styling

    /// Per-character style, packed: colour index (bits 0–3) and flags. Styles are computed into an
    /// array first and written to the text storage afterwards in ascending runs: applying each
    /// regex match directly split runs in the middle of a document-sized run array, which made
    /// highlighting quadratic (minutes for a few MB).
    private enum Style {
        static let colorMask: UInt16 = 0x000F
        static let bold: UInt16 = 1 << 4
        static let italic: UInt16 = 1 << 5
        static let strike: UInt16 = 1 << 6
        static let underline: UInt16 = 1 << 7
        static let codeBackground: UInt16 = 1 << 8
        // Colour indices
        static let text: UInt16 = 0, muted: UInt16 = 1, heading: UInt16 = 2, quote: UInt16 = 3,
                   list: UInt16 = 4, tag: UInt16 = 5, link: UInt16 = 6, code: UInt16 = 7
    }

    private static let palette: [NSColor] = [EditorColors.text, EditorColors.muted, EditorColors.heading, EditorColors.quote,
                                             EditorColors.list, EditorColors.tag, EditorColors.link, EditorColors.code]
    private lazy var italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    private lazy var boldItalicFont = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)
    private var attributeCache: [UInt16: [NSAttributedString.Key: Any]] = [:]

    private func attributes(_ style: UInt16) -> [NSAttributedString.Key: Any] {
        if let a = attributeCache[style] { return a }
        let b = style & Style.bold != 0, i = style & Style.italic != 0
        var a: [NSAttributedString.Key: Any] = [
            .font: b && i ? boldItalicFont : b ? boldFont : i ? italicFont : baseFont,
            .foregroundColor: Self.palette[Int(style & Style.colorMask)],
            .paragraphStyle: paragraph,
        ]
        if style & Style.strike != 0 { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if style & Style.underline != 0 { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style & Style.codeBackground != 0 { a[.backgroundColor] = EditorColors.codeBackground }
        attributeCache[style] = a
        return a
    }

    private func apply(_ ts: NSTextStorage, target: NSRange, structure: Structure) {
        guard target.length > 0 else { return }
        let s = ts.string as NSString
        let str = ts.string
        var styles = [UInt16](repeating: Style.text, count: target.length)
        let base = target.location

        func mark(_ range: NSRange, _ change: (inout UInt16) -> Void) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            let r = NSIntersectionRange(range, target)
            guard r.length > 0 else { return }
            for k in (r.location - base)..<(NSMaxRange(r) - base) { change(&styles[k]) }
        }
        func color(_ range: NSRange, _ c: UInt16) { mark(range) { $0 = ($0 & ~Style.colorMask) | c } }
        func flag(_ range: NSRange, _ f: UInt16) { mark(range) { $0 |= f } }
        func each(_ r: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            r.enumerateMatches(in: str, range: target) { m, _, _ in if let m = m { body(m) } }
        }

        each(heading) { m in
            flag(m.range, Style.bold)
            color(m.range, Style.heading)
            color(m.range(at: 1), Style.muted)
        }
        each(setext) { m in
            flag(m.range, Style.bold)
            color(m.range, Style.heading)
            color(m.range(at: 1), Style.muted)
        }
        each(quote) { m in
            color(m.range(at: 1), Style.muted)
            color(m.range(at: 2), Style.quote)
        }
        each(bold) { m in
            flag(m.range, Style.bold)
            let pl = 2 // "**" or "__"
            color(NSRange(location: m.range.location, length: pl), Style.muted)
            color(NSRange(location: NSMaxRange(m.range) - pl, length: pl), Style.muted)
        }
        for r in [italicStar, italicUnderscore] {
            each(r) { m in
                flag(m.range, Style.italic)
                color(NSRange(location: m.range.location, length: 1), Style.muted)
                color(NSRange(location: NSMaxRange(m.range) - 1, length: 1), Style.muted)
            }
        }
        each(strike) { m in
            flag(m.range, Style.strike)
            color(m.range, Style.muted)
        }
        each(listMarker) { m in color(m.range(at: 1), Style.list) }
        each(taskBox) { m in color(m.range(at: 1), Style.list) }
        each(rule) { m in color(m.range, Style.muted) }
        each(tablePipe) { m in
            for k in m.range.location..<NSMaxRange(m.range) where s.character(at: k) == 124 {
                color(NSRange(location: k, length: 1), Style.muted)
            }
        }
        each(htmlTag) { m in color(m.range, Style.tag) }
        for r in [link, refLink] {
            each(r) { m in
                color(m.range, Style.muted)
                color(m.range(at: 2), Style.link)
            }
        }
        each(refDef) { m in color(m.range, Style.muted) }
        each(footnote) { m in color(m.range, Style.link) }
        for r in [bareURL, angleLink] {
            each(r) { m in
                color(m.range, Style.link)
                flag(m.range, Style.underline)
            }
        }
        for c in structure.comments {
            mark(c) { $0 = ($0 & ~(Style.bold | Style.colorMask)) | Style.italic | Style.muted }
        }
        each(inlineCode) { m in
            mark(m.range) { $0 = ($0 & Style.underline) | Style.code | Style.codeBackground }
        }
        // Fenced code blocks override everything inside them.
        for c in structure.code {
            mark(c) { $0 = Style.code | Style.codeBackground }
        }

        // Write in ascending runs after collapsing the range to one run: each write then only
        // splits the tail run, so no document-sized run array is shifted.
        ts.beginEditing()
        ts.setAttributes(baseAttributes, range: target)
        var runStart = 0
        while runStart < styles.count {
            let st = styles[runStart]
            var runEnd = runStart + 1
            while runEnd < styles.count, styles[runEnd] == st { runEnd += 1 }
            if st != Style.text {
                ts.setAttributes(attributes(st), range: NSRange(location: base + runStart, length: runEnd - runStart))
            }
            runStart = runEnd
        }
        ts.endEditing()
    }
}
