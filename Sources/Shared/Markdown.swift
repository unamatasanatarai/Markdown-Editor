import Foundation

/// GitHub Flavored Markdown → HTML renderer with no external dependencies.
/// Shared by the editor app and the Quick Look extension.
///
/// Supports: ATX/setext headings, paragraphs, emphasis/strong/strikethrough, inline code,
/// fenced/indented code, blockquotes, GitHub alerts, ordered/unordered/task lists (nested),
/// tables with alignment, thematic breaks, links/images (inline + reference), autolinks
/// (angle + bare URLs), raw HTML, footnotes, hard line breaks and heading anchors.
public enum Markdown {
    /// `allowRemoteResources`: when false, no output references a remote resource (images from
    /// http(s) are replaced by their alt text). Used where a loader would fetch them unattended.
    public static func html(from markdown: String, allowRemoteResources: Bool = true) -> String {
        fragments(from: markdown, allowRemoteResources: allowRemoteResources).html.joined()
    }

    /// The rendered document as one HTML fragment per top-level block (plus the footnotes section
    /// last); `html.joined()` is exactly `html(from:)`. `selfContained` is true when every fragment
    /// that contains raw HTML has balanced tags, so each fragment parses the same on its own as
    /// inside the whole document and the preview may replace fragments individually (PERF-002).
    public static func fragments(from markdown: String, allowRemoteResources: Bool = true) -> (html: [String], selfContained: Bool) {
        let ctx = MDContext()
        ctx.allowRemote = allowRemoteResources
        let lines = MDLine.split(markdown)
        let blocks = MDBlockParser(ctx: ctx).parse(lines).blocks
        return MDRenderer(ctx: ctx).renderFragments(blocks)
    }

    /// Whether the tags in renderer output are balanced (void elements aside). Only valid for this
    /// renderer's output: text and attribute values never contain a raw `<` there.
    static func tagsBalanced(_ html: String) -> Bool {
        let u = Array(html.utf8)
        var stack: [ArraySlice<UInt8>] = []
        var i = 0
        func isNameByte(_ b: UInt8) -> Bool {
            (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || b == 45
        }
        while i < u.count {
            guard u[i] == 60 else { i += 1; continue } // "<"
            var j = i + 1
            let closing = j < u.count && u[j] == 47
            if closing { j += 1 }
            let start = j
            while j < u.count, isNameByte(u[j]) { j += 1 }
            let name = u[start..<j]
            while j < u.count, u[j] != 62 { j += 1 } // ">"
            if name.isEmpty { return false }
            if closing {
                guard let top = stack.popLast(), top.elementsEqual(name) else { return false }
            } else if !voidElements.contains(String(decoding: name, as: UTF8.self)) {
                stack.append(name)
            }
            i = j + 1
        }
        return stack.isEmpty
    }

    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr",
    ]
}

// MARK: - AST

indirect enum MDBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(info: String, text: String)
    case quote([MDBlock])
    case alert(kind: String, blocks: [MDBlock])
    case list(ordered: Bool, start: Int, tight: Bool, items: [MDListItem])
    case rule
    case html(String)
    case table(header: [String], aligns: [MDAlign], rows: [[String]])
}

struct MDListItem {
    var checked: Bool?
    var blocks: [MDBlock]
}

enum MDAlign { case none, left, center, right }

final class MDContext {
    var refs: [String: (url: String, title: String?)] = [:]
    var footnoteDefs: [String: [MDBlock]] = [:]
    var footnoteOrder: [String] = []
    var slugCounts: [String: Int] = [:]
    var footnoteIndex: [String: Int] = [:]
    var allowRemote = true
    /// Number of raw HTML pieces emitted so far (see `Markdown.fragments`).
    var rawHTMLCount = 0

    func footnoteNumber(_ id: String) -> Int {
        if let i = footnoteIndex[id] { return i }
        footnoteOrder.append(id)
        footnoteIndex[id] = footnoteOrder.count
        return footnoteOrder.count
    }
}

// MARK: - Line helpers

enum MDLine {
    /// Lines as native UTF-8 Swift strings. The input is often NSString-backed (`NSTextView.string`)
    /// and `components(separatedBy:)` returns NSString-backed lines too; every character access on
    /// those goes through Objective-C, which made rendering ~2.5× slower (PERF-001).
    static func split(_ s: String) -> [String] {
        var t = s
        t.makeContiguousUTF8()
        if t.utf8.contains(13) {
            t = t.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            t.makeContiguousUTF8()
        }
        if t.utf8.contains(0) {
            t = t.replacingOccurrences(of: "\u{0}", with: "\u{FFFD}")
            t.makeContiguousUTF8()
        }
        // Split on the byte level: "\n" is never part of another UTF-8 sequence, and "\r\n" is gone.
        return t.utf8.split(separator: 10, omittingEmptySubsequences: false).map {
            expandLeadingTabs(String(Substring($0)))
        }
    }

    /// Expands tabs that appear in the leading run of whitespace / blockquote markers.
    static func expandLeadingTabs(_ l: String) -> String {
        guard l.utf8.contains(9), l.contains("\t") else { return l }
        var out = ""
        var col = 0
        var idx = l.startIndex
        while idx < l.endIndex {
            let c = l[idx]
            if c == "\t" {
                let n = 4 - col % 4
                out += String(repeating: " ", count: n)
                col += n
            } else if c == " " || c == ">" {
                out.append(c)
                col += 1
            } else {
                break
            }
            idx = l.index(after: idx)
        }
        return out + l[idx...]
    }

    static func indent(_ s: String) -> Int {
        var n = 0
        for c in s.utf8 {
            if c == 32 { n += 1 } else { break }
        }
        return n
    }

    static func isBlank(_ s: String) -> Bool {
        s.utf8.allSatisfy { $0 == 32 || $0 == 9 }
    }

    static func dropIndent(_ s: String, _ n: Int) -> String {
        var k = 0
        var idx = s.startIndex
        while k < n, idx < s.endIndex, s[idx] == " " {
            idx = s.index(after: idx)
            k += 1
        }
        return String(s[idx...])
    }

    static func trimLeading(_ s: String) -> String {
        String(s.drop(while: { $0 == " " || $0 == "\t" }))
    }

    static func trimTrailing(_ s: String) -> String {
        var t = Substring(s)
        while let l = t.last, l == " " || l == "\t" { t = t.dropLast() }
        return String(t)
    }

    static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Block parser

final class MDBlockParser {
    let ctx: MDContext

    init(ctx: MDContext) { self.ctx = ctx }

    /// Maximum container nesting (quotes, list items, footnotes). Deeper content is kept as plain
    /// paragraph text, so crafted input cannot exhaust the (small) stack of a dispatch queue.
    static let maxDepth = 16
    private var depth = 0

    private func parseNested(_ lines: [String]) -> (blocks: [MDBlock], loose: Bool) {
        if depth >= Self.maxDepth {
            let text = lines.map { MDLine.trimLeading($0) }.filter { !$0.isEmpty }.joined(separator: "\n")
            return (text.isEmpty ? [] : [.paragraph(text)], false)
        }
        depth += 1
        defer { depth -= 1 }
        return parse(lines)
    }

    private static let blockTags: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center",
        "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption",
        "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head",
        "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav",
        "noframes", "ol", "optgroup", "option", "p", "param", "picture", "search", "section", "source",
        "summary", "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul", "video", "audio",
    ]

    private static let refDefRegex = try! NSRegularExpression(
        pattern: #"^ {0,3}\[((?:[^\]\\]|\\.)+)\]:[ \t]*<?([^\s>]*)>?(?:[ \t]+(?:"([^"]*)"|'([^']*)'|\(([^)]*)\)))?[ \t]*$"#)
    private static let footnoteDefRegex = try! NSRegularExpression(pattern: #"^ {0,3}\[\^([^\]\s]+)\]:[ \t]?(.*)$"#)
    private static let type7Regex = try! NSRegularExpression(
        pattern: #"^ {0,3}(?:<[A-Za-z][A-Za-z0-9-]*(?:\s+[A-Za-z_:][A-Za-z0-9_.:-]*(?:\s*=\s*(?:[^\s"'=<>`]+|'[^']*'|"[^"]*"))?)*\s*/?>|</[A-Za-z][A-Za-z0-9-]*\s*>)\s*$"#)
    private static let alertRegex = try! NSRegularExpression(
        pattern: #"^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$"#, options: [.caseInsensitive])
    private static let taskRegex = try! NSRegularExpression(pattern: #"^\[([ xX])\](?:[ \t]+|$)"#)

    /// Parses lines into blocks. `loose` reports whether a blank line separated two blocks at this level.
    func parse(_ lines: [String]) -> (blocks: [MDBlock], loose: Bool) {
        var blocks: [MDBlock] = []
        var i = 0
        var pendingBlank = false
        var loose = false
        while i < lines.count {
            let line = lines[i]
            if MDLine.isBlank(line) {
                if !blocks.isEmpty { pendingBlank = true }
                i += 1
                continue
            }
            if pendingBlank {
                loose = true
                pendingBlank = false
            }
            if MDLine.indent(line) >= 4 {
                blocks.append(parseIndentedCode(lines, &i))
                continue
            }
            if let b = parseFence(lines, &i) { blocks.append(b); continue }
            if let h = atxHeading(line) {
                blocks.append(.heading(level: h.level, text: h.text))
                i += 1
                continue
            }
            if isRule(line) {
                blocks.append(.rule)
                i += 1
                continue
            }
            if quoteStrip(line) != nil {
                blocks.append(parseQuote(lines, &i))
                continue
            }
            if let b = parseHTMLBlock(lines, &i) { blocks.append(b); continue }
            if parseFootnoteDef(lines, &i) { continue }
            if listMarker(line) != nil {
                blocks.append(parseList(lines, &i))
                continue
            }
            if let t = parseTable(lines, &i) { blocks.append(t); continue }
            blocks.append(contentsOf: parseParagraph(lines, &i))
        }
        return (blocks, loose)
    }

    // MARK: Leaf detection

    func atxHeading(_ line: String) -> (level: Int, text: String)? {
        let ind = MDLine.indent(line)
        guard ind < 4 else { return nil }
        var s = Substring(line).dropFirst(ind)
        var level = 0
        while s.first == "#" {
            level += 1
            s = s.dropFirst()
        }
        guard (1...6).contains(level) else { return nil }
        if let f = s.first, f != " " && f != "\t" { return nil }
        var text = MDLine.trim(String(s))
        // Optional closing sequence: a trailing run of "#" at the start or after a space/tab
        // (`text` is already trimmed, so nothing follows the run). Same as the regex
        // `(^|[ \t])#+[ \t]*$`, without compiling a regex per heading.
        if text.last == "#" {
            var cut = text.endIndex
            while cut > text.startIndex, text[text.index(before: cut)] == "#" { cut = text.index(before: cut) }
            if cut == text.startIndex {
                text = ""
            } else {
                let before = text.index(before: cut)
                if text[before] == " " || text[before] == "\t" { text = MDLine.trim(String(text[..<before])) }
            }
        }
        return (level, text)
    }

    func isRule(_ line: String) -> Bool {
        guard MDLine.indent(line) < 4 else { return false }
        var ch: Character?
        var count = 0
        for c in line where c != " " && c != "\t" {
            guard c == "*" || c == "-" || c == "_" else { return false }
            if ch == nil { ch = c } else if ch != c { return false }
            count += 1
        }
        return count >= 3
    }

    func setextLevel(_ line: String) -> Int? {
        guard MDLine.indent(line) < 4 else { return nil }
        let t = MDLine.trim(line)
        guard let f = t.first, f == "=" || f == "-" else { return nil }
        guard t.allSatisfy({ $0 == f }) else { return nil }
        return f == "=" ? 1 : 2
    }

    func fenceOpen(_ line: String) -> (char: Character, len: Int, indent: Int, info: String)? {
        let ind = MDLine.indent(line)
        guard ind < 4 else { return nil }
        let rest = Substring(line).dropFirst(ind)
        guard let c = rest.first, c == "`" || c == "~" else { return nil }
        let len = rest.prefix(while: { $0 == c }).count
        guard len >= 3 else { return nil }
        let info = MDLine.trim(String(rest.dropFirst(len)))
        if c == "`" && info.contains("`") { return nil }
        return (c, len, ind, info)
    }

    func quoteStrip(_ line: String) -> String? {
        let ind = MDLine.indent(line)
        guard ind < 4 else { return nil }
        let r = Substring(line).dropFirst(ind)
        guard r.first == ">" else { return nil }
        var rest = r.dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        return String(rest)
    }

    func htmlBlockKind(_ line: String) -> Int? {
        let ind = MDLine.indent(line)
        guard ind < 4 else { return nil }
        let r = Substring(line).dropFirst(ind)
        guard r.first == "<" else { return nil }
        let lower = r.lowercased()
        for t in ["<script", "<pre", "<style", "<textarea"] where lower.hasPrefix(t) {
            let after = lower.dropFirst(t.count).first
            if after == nil || after == " " || after == ">" || after == "\t" { return 1 }
        }
        if lower.hasPrefix("<!--") { return 2 }
        var s = Substring(lower).dropFirst()
        if s.first == "/" { s = s.dropFirst() }
        let name = s.prefix(while: { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        guard let f = name.first, f.isLetter else { return nil }
        let after = s.dropFirst(name.count).first
        if Self.blockTags.contains(String(name)) && (after == nil || after == " " || after == ">" || after == "/" || after == "\t") {
            return 6
        }
        let ns = line as NSString
        if Self.type7Regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil { return 7 }
        return nil
    }

    struct Marker {
        let ordered: Bool
        let delim: Character
        let start: Int
        let indent: Int
        let contentOffset: Int
        let empty: Bool
        /// The line's characters up to `contentOffset` are single-byte ASCII, so the offset is also
        /// a UTF-8 offset and the item content can be sliced from `utf8` directly.
        var asciiPrefix = false
    }

    /// List marker detection on UTF-8 bytes (marker syntax is ASCII). Whenever it would have to
    /// classify a non-ASCII byte, where grapheme clustering could change the result, it defers to
    /// the Character-based version so behaviour stays identical (PERF-005).
    func listMarker(_ line: String) -> Marker? {
        let ind = MDLine.indent(line)
        guard ind < 4 else { return nil }
        let u = line.utf8
        let n = u.count
        var idx = u.index(u.startIndex, offsetBy: ind)
        var p = ind
        guard p < n else { return nil }
        func byte() -> UInt8 { u[idx] }
        func advance() { idx = u.index(after: idx); p += 1 }
        if byte() >= 0x80 { return listMarkerSlow(line) }
        var ordered = false
        var start = 1
        let delim: Character
        let b0 = byte()
        if b0 == 45 || b0 == 43 || b0 == 42 { // - + *
            delim = Character(Unicode.Scalar(b0))
            advance()
        } else {
            var value = 0, digits = 0
            while p < n, byte() >= 48, byte() <= 57, digits < 9 {
                value = value * 10 + Int(byte() - 48)
                digits += 1
                advance()
            }
            if p < n, byte() >= 0x80 { return listMarkerSlow(line) }
            guard digits > 0, p < n, byte() == 46 || byte() == 41 else { return nil } // . )
            delim = Character(Unicode.Scalar(byte()))
            advance()
            ordered = true
            start = value
        }
        if p == n {
            return Marker(ordered: ordered, delim: delim, start: start, indent: ind, contentOffset: p + 1, empty: true, asciiPrefix: true)
        }
        let c = byte()
        if c >= 0x80 { return listMarkerSlow(line) }
        if c == 9 {
            return Marker(ordered: ordered, delim: delim, start: start, indent: ind, contentOffset: p + 1, empty: p + 1 >= n, asciiPrefix: true)
        }
        guard c == 32 else { return nil }
        let p0 = p
        while p < n, byte() == 32 { advance() }
        // A combining mark after the last space would merge with it into one Character.
        if p < n, byte() >= 0x80 { return listMarkerSlow(line) }
        if p == n {
            return Marker(ordered: ordered, delim: delim, start: start, indent: ind, contentOffset: p0 + 1, empty: true, asciiPrefix: true)
        }
        var sp = p - p0
        if sp > 4 { sp = 1 }
        return Marker(ordered: ordered, delim: delim, start: start, indent: ind, contentOffset: p0 + sp, empty: false, asciiPrefix: true)
    }

    /// Reference implementation on Characters, used when the marker region contains non-ASCII text.
    func listMarkerSlow(_ line: String) -> Marker? {
        let ind = MDLine.indent(line)
        guard ind < 4 else { return nil }
        let chars = Array(line)
        var p = ind
        guard p < chars.count else { return nil }
        var ordered = false
        var start = 1
        let delim: Character
        if chars[p] == "-" || chars[p] == "+" || chars[p] == "*" {
            delim = chars[p]
            p += 1
        } else {
            var digits = ""
            while p < chars.count, chars[p].isASCII, chars[p].isNumber, digits.count < 9 {
                digits.append(chars[p])
                p += 1
            }
            guard !digits.isEmpty, p < chars.count, chars[p] == "." || chars[p] == ")" else { return nil }
            delim = chars[p]
            p += 1
            ordered = true
            start = Int(digits) ?? 1
        }
        if p == chars.count {
            return Marker(ordered: ordered, delim: delim, start: start, indent: ind, contentOffset: p + 1, empty: true)
        }
        if chars[p] == "\t" {
            return Marker(ordered: ordered, delim: delim, start: start, indent: ind, contentOffset: p + 1, empty: p + 1 >= chars.count)
        }
        guard chars[p] == " " else { return nil }
        var q = p
        while q < chars.count, chars[q] == " " { q += 1 }
        if q == chars.count {
            return Marker(ordered: ordered, delim: delim, start: start, indent: ind, contentOffset: p + 1, empty: true)
        }
        var sp = q - p
        if sp > 4 { sp = 1 }
        return Marker(ordered: ordered, delim: delim, start: start, indent: ind, contentOffset: p + sp, empty: false)
    }

    func interruptsParagraph(_ line: String) -> Bool {
        if MDLine.indent(line) >= 4 { return false }
        if atxHeading(line) != nil || fenceOpen(line) != nil || isRule(line) || quoteStrip(line) != nil {
            return true
        }
        if let k = htmlBlockKind(line), k != 7 { return true }
        if let m = listMarker(line), !m.empty, !m.ordered || m.start == 1 { return true }
        if line.utf8.contains(94), line.contains("[^") {
            let ns = line as NSString
            if Self.footnoteDefRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil { return true }
        }
        return false
    }

    // MARK: Block constructs

    func parseIndentedCode(_ lines: [String], _ i: inout Int) -> MDBlock {
        var body: [String] = []
        while i < lines.count {
            let l = lines[i]
            if MDLine.isBlank(l) {
                body.append("")
            } else if MDLine.indent(l) >= 4 {
                body.append(MDLine.dropIndent(l, 4))
            } else {
                break
            }
            i += 1
        }
        while let last = body.last, MDLine.isBlank(last) {
            body.removeLast()
            i -= 1
        }
        return .code(info: "", text: body.joined(separator: "\n"))
    }

    func parseFence(_ lines: [String], _ i: inout Int) -> MDBlock? {
        guard let f = fenceOpen(lines[i]) else { return nil }
        i += 1
        var body: [String] = []
        while i < lines.count {
            let l = lines[i]
            let ind = MDLine.indent(l)
            if ind < 4 {
                let r = Substring(l).dropFirst(ind)
                let n = r.prefix(while: { $0 == f.char }).count
                if n >= f.len && MDLine.isBlank(String(r.dropFirst(n))) {
                    i += 1
                    break
                }
            }
            body.append(MDLine.dropIndent(l, f.indent))
            i += 1
        }
        return .code(info: f.info, text: body.joined(separator: "\n"))
    }

    func parseQuote(_ lines: [String], _ i: inout Int) -> MDBlock {
        var q: [String] = []
        var inFence = false
        while i < lines.count {
            let l = lines[i]
            if let s = quoteStrip(l) {
                if fenceOpen(s) != nil { inFence.toggle() }
                q.append(s)
                i += 1
                continue
            }
            // Lazy paragraph continuation.
            if !MDLine.isBlank(l), let last = q.last, !MDLine.isBlank(last), !inFence,
               !interruptsParagraph(l), atxHeading(last) == nil {
                q.append(l)
                i += 1
                continue
            }
            break
        }
        if let first = q.first {
            let ns = first as NSString
            if let m = Self.alertRegex.firstMatch(in: first, range: NSRange(location: 0, length: ns.length)) {
                let kind = ns.substring(with: m.range(at: 1)).lowercased()
                return .alert(kind: kind, blocks: parseNested(Array(q.dropFirst())).blocks)
            }
        }
        return .quote(parseNested(q).blocks)
    }

    func parseHTMLBlock(_ lines: [String], _ i: inout Int) -> MDBlock? {
        guard let kind = htmlBlockKind(lines[i]) else { return nil }
        var out: [String] = []
        switch kind {
        case 1:
            let closers = ["</script>", "</pre>", "</style>", "</textarea>"]
            while i < lines.count {
                let l = lines[i]
                out.append(l)
                i += 1
                let lower = l.lowercased()
                if closers.contains(where: { lower.contains($0) }) { break }
            }
        case 2:
            while i < lines.count {
                let l = lines[i]
                out.append(l)
                i += 1
                if l.contains("-->") { break }
            }
        default:
            while i < lines.count, !MDLine.isBlank(lines[i]) {
                out.append(lines[i])
                i += 1
            }
        }
        return .html(out.joined(separator: "\n"))
    }

    /// Cheap necessary condition for `footnoteDefRegex`: up to 3 spaces, then "[^".
    static func mayStartFootnoteDef(_ line: String) -> Bool {
        var it = line.utf8.makeIterator()
        var spaces = 0
        while let b = it.next() {
            if b == 32 { spaces += 1; if spaces > 3 { return false }; continue }
            return b == 91 && it.next() == 94
        }
        return false
    }

    func parseFootnoteDef(_ lines: [String], _ i: inout Int) -> Bool {
        let line = lines[i]
        guard Self.mayStartFootnoteDef(line) else { return false }
        let ns = line as NSString
        guard let m = Self.footnoteDefRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return false
        }
        let id = ns.substring(with: m.range(at: 1)).lowercased()
        var body = [ns.substring(with: m.range(at: 2))]
        i += 1
        while i < lines.count {
            let l = lines[i]
            if MDLine.isBlank(l) {
                var j = i
                while j < lines.count, MDLine.isBlank(lines[j]) { j += 1 }
                if j < lines.count, MDLine.indent(lines[j]) >= 4 {
                    body.append(contentsOf: Array(repeating: "", count: j - i))
                    i = j
                    continue
                }
                break
            }
            if MDLine.indent(l) >= 4 {
                body.append(MDLine.dropIndent(l, 4))
            } else if let last = body.last, !MDLine.isBlank(last), !interruptsParagraph(l), listMarker(l) == nil {
                body.append(l)
            } else {
                break
            }
            i += 1
        }
        if ctx.footnoteDefs[id] == nil {
            ctx.footnoteDefs[id] = parseNested(body).blocks
        }
        return true
    }

    func parseList(_ lines: [String], _ i: inout Int) -> MDBlock {
        guard let first = listMarker(lines[i]) else { return .paragraph(lines[i]) }
        var items: [MDListItem] = []
        var tight = true

        while i < lines.count, let m = listMarker(lines[i]), m.ordered == first.ordered, m.delim == first.delim {
            if !items.isEmpty && isRule(lines[i]) { break }
            let off = m.contentOffset
            let firstLine: String
            if m.asciiPrefix {
                let u = lines[i].utf8
                firstLine = m.empty || off >= u.count ? "" : String(Substring(u.dropFirst(off)))
            } else {
                let chars = Array(lines[i])
                firstLine = m.empty || off >= chars.count ? "" : String(chars[off...])
            }
            var itemLines: [String] = [firstLine]
            var inFence = fenceOpen(itemLines[0]) != nil
            i += 1
            while i < lines.count {
                let l = lines[i]
                if MDLine.isBlank(l) {
                    // An item may begin with at most one blank line.
                    if m.empty && itemLines.count == 1 && itemLines[0].isEmpty { break }
                    itemLines.append("")
                    i += 1
                    continue
                }
                if MDLine.indent(l) >= off {
                    let stripped = MDLine.dropIndent(l, off)
                    if fenceOpen(stripped) != nil { inFence.toggle() }
                    itemLines.append(stripped)
                    i += 1
                    continue
                }
                // Lazy continuation of a paragraph.
                if let last = itemLines.last, !MDLine.isBlank(last), !inFence, !interruptsParagraph(l),
                   listMarker(l) == nil, atxHeading(last) == nil, fenceOpen(last) == nil {
                    itemLines.append(MDLine.trimLeading(l))
                    i += 1
                    continue
                }
                break
            }
            var trailingBlank = 0
            while itemLines.count > 1, let last = itemLines.last, MDLine.isBlank(last) {
                itemLines.removeLast()
                trailingBlank += 1
            }

            var checked: Bool?
            if let f = itemLines.first {
                let ns = f as NSString
                if let tm = Self.taskRegex.firstMatch(in: f, range: NSRange(location: 0, length: ns.length)) {
                    checked = ns.substring(with: tm.range(at: 1)) != " "
                    itemLines[0] = ns.substring(from: tm.range.length)
                }
            }
            let (blocks, innerLoose) = parseNested(itemLines)
            if innerLoose { tight = false }
            items.append(MDListItem(checked: checked, blocks: blocks))

            if trailingBlank > 0 {
                if i < lines.count, let nm = listMarker(lines[i]), nm.ordered == first.ordered,
                   nm.delim == first.delim, !isRule(lines[i]) {
                    tight = false
                } else {
                    i -= trailingBlank
                    break
                }
            }
        }
        return .list(ordered: first.ordered, start: first.start, tight: tight, items: items)
    }

    // MARK: Tables

    func splitRow(_ line: String) -> [String] {
        var s = MDLine.trim(line)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") && !s.hasSuffix("\\|") { s.removeLast() }
        var cells: [String] = []
        var cur = ""
        var escaped = false
        for c in s {
            if escaped {
                if c != "|" { cur.append("\\") }
                cur.append(c)
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == "|" {
                cells.append(MDLine.trim(cur))
                cur = ""
            } else {
                cur.append(c)
            }
        }
        if escaped { cur.append("\\") }
        cells.append(MDLine.trim(cur))
        return cells
    }

    func delimiterRow(_ line: String) -> [MDAlign]? {
        guard MDLine.indent(line) < 4 else { return nil }
        let t = MDLine.trim(line)
        guard t.utf8.contains(45), t.contains("-"), t.allSatisfy({ "|:- \t".contains($0) }) else { return nil }
        let cells = splitRow(t)
        guard t.contains("|") || cells.count > 1 else { return nil }
        var aligns: [MDAlign] = []
        for c in cells {
            guard !c.isEmpty, c.contains("-") else { return nil }
            let core = c.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !core.isEmpty, core.allSatisfy({ $0 == "-" }) else { return nil }
            let l = c.hasPrefix(":"), r = c.hasSuffix(":")
            aligns.append(l && r ? .center : l ? .left : r ? .right : .none)
        }
        return aligns
    }

    func isTableStart(_ header: String, _ delim: String) -> Bool {
        guard header.utf8.contains(124), header.contains("|"), MDLine.indent(header) < 4, let a = delimiterRow(delim) else { return false }
        return splitRow(header).count == a.count
    }

    func parseTable(_ lines: [String], _ i: inout Int) -> MDBlock? {
        guard i + 1 < lines.count, isTableStart(lines[i], lines[i + 1]),
              let aligns = delimiterRow(lines[i + 1]) else { return nil }
        let header = splitRow(lines[i])
        i += 2
        var rows: [[String]] = []
        while i < lines.count, !MDLine.isBlank(lines[i]), !interruptsParagraph(lines[i]) {
            var cells = splitRow(lines[i])
            if cells.count < header.count {
                cells += Array(repeating: "", count: header.count - cells.count)
            } else if cells.count > header.count {
                cells = Array(cells.prefix(header.count))
            }
            rows.append(cells)
            i += 1
        }
        return .table(header: header, aligns: aligns, rows: rows)
    }

    // MARK: Paragraphs

    func parseParagraph(_ lines: [String], _ i: inout Int) -> [MDBlock] {
        var para: [String] = [lines[i]]
        i += 1
        while i < lines.count {
            let l = lines[i]
            if MDLine.isBlank(l) { break }
            if let lvl = setextLevel(l) {
                if !finishParagraph(para, heading: nil, onlyRefs: true).isEmpty {
                    let leftover = finishParagraph(para, heading: lvl, onlyRefs: false)
                    i += 1
                    return [.heading(level: lvl, text: leftover.joined(separator: "\n"))]
                }
                if lvl == 2 && isRule(l) { break }
            }
            if interruptsParagraph(l) { break }
            if i + 1 < lines.count, isTableStart(l, lines[i + 1]) { break }
            para.append(l)
            i += 1
        }
        let text = finishParagraph(para, heading: nil, onlyRefs: false).joined(separator: "\n")
        return text.isEmpty ? [] : [.paragraph(text)]
    }

    /// Strips leading link reference definitions and returns the remaining (trimmed) paragraph lines.
    @discardableResult
    func finishParagraph(_ lines: [String], heading: Int?, onlyRefs: Bool) -> [String] {
        var ls = lines
        var defs: [(String, String, String?)] = []
        while let f = ls.first {
            let ns = f as NSString
            guard let m = Self.refDefRegex.firstMatch(in: f, range: NSRange(location: 0, length: ns.length)) else { break }
            let label = ns.substring(with: m.range(at: 1))
            if label.hasPrefix("^") { break }
            var title: String?
            for g in 3...5 where m.range(at: g).location != NSNotFound {
                title = ns.substring(with: m.range(at: g))
            }
            defs.append((label, ns.substring(with: m.range(at: 2)), title))
            ls.removeFirst()
        }
        if !onlyRefs {
            for (label, url, title) in defs {
                let key = MDInline.normalizeLabel(label)
                if ctx.refs[key] == nil { ctx.refs[key] = (url, title) }
            }
        }
        var out = ls.map { MDLine.trimLeading($0) }
        if let last = out.last { out[out.count - 1] = MDLine.trimTrailing(last) }
        if out.count == 1 && out[0].isEmpty { return [] }
        return out
    }
}

// MARK: - Renderer

final class MDRenderer {
    let ctx: MDContext
    private lazy var inline = MDInline(ctx: ctx)

    init(ctx: MDContext) { self.ctx = ctx }

    func renderDocument(_ blocks: [MDBlock]) -> String {
        renderFragments(blocks).html.joined()
    }

    func renderFragments(_ blocks: [MDBlock]) -> (html: [String], selfContained: Bool) {
        var out: [String] = []
        out.reserveCapacity(blocks.count + 1)
        var selfContained = true
        func add(_ render: () -> String) {
            let raw = ctx.rawHTMLCount
            let h = render()
            if selfContained, ctx.rawHTMLCount != raw, !Markdown.tagsBalanced(h) { selfContained = false }
            out.append(h)
        }
        for b in blocks { add { renderBlock(b, tight: false) } }
        if !ctx.footnoteOrder.isEmpty { add { renderFootnotes() } }
        return (out, selfContained)
    }

    private func renderFootnotes() -> String {
        var items = ""
        var k = 0
        while k < ctx.footnoteOrder.count { // footnote bodies may reference further footnotes
            let id = ctx.footnoteOrder[k]
            let attr = MDEscape.attr(id)
            var body = render(ctx.footnoteDefs[id] ?? [])
            let back = " <a href=\"#fnref-\(attr)\" class=\"footnote-backref\" aria-label=\"Back to reference \(k + 1)\">↩</a>"
            if body.hasSuffix("</p>\n") {
                body = String(body.dropLast(5)) + back + "</p>\n"
            } else {
                body += "<p>\(back)</p>\n"
            }
            items += "<li id=\"fn-\(attr)\">\n\(body)</li>\n"
            k += 1
        }
        return "<section class=\"footnotes\" data-footnotes>\n<ol>\n\(items)</ol>\n</section>\n"
    }

    func render(_ blocks: [MDBlock], tight: Bool = false) -> String {
        var out = ""
        for b in blocks { out += renderBlock(b, tight: tight) }
        return out
    }

    private func renderBlock(_ b: MDBlock, tight: Bool) -> String {
        switch b {
        case let .heading(level, text):
            let inner = inline.render(text)
            let id = slug(MDEscape.plainText(inner))
            return "<h\(level) id=\"\(MDEscape.attr(id))\">\(inner)</h\(level)>\n"
        case let .paragraph(text):
            let inner = inline.render(text)
            return tight ? inner + "\n" : "<p>\(inner)</p>\n"
        case let .code(info, text):
            let lang = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            let cls = lang.isEmpty ? "" : " class=\"language-\(MDEscape.attr(MDInline.unescapePunct(lang)))\""
            let body = text.isEmpty ? "" : MDEscape.html(text) + "\n"
            return "<pre><code\(cls)>\(body)</code></pre>\n"
        case let .quote(blocks):
            return "<blockquote>\n\(render(blocks))</blockquote>\n"
        case let .alert(kind, blocks):
            let title = kind.prefix(1).uppercased() + kind.dropFirst()
            return "<div class=\"markdown-alert markdown-alert-\(kind)\">\n<p class=\"markdown-alert-title\">\(MDAlertIcons.svg(kind))\(title)</p>\n\(render(blocks))</div>\n"
        case let .list(ordered, start, isTight, items):
            let tag = ordered ? "ol" : "ul"
            let startAttr = ordered && start != 1 ? " start=\"\(start)\"" : ""
            let hasTask = items.contains { $0.checked != nil }
            let cls = hasTask ? " class=\"contains-task-list\"" : ""
            var out = "<\(tag)\(startAttr)\(cls)>\n"
            for item in items { out += renderItem(item, tight: isTight) }
            return out + "</\(tag)>\n"
        case .rule:
            return "<hr>\n"
        case let .html(s):
            ctx.rawHTMLCount += 1
            return HTMLSanitizer.sanitize(s, allowRemote: ctx.allowRemote) + "\n"
        case let .table(header, aligns, rows):
            func style(_ i: Int) -> String {
                switch i < aligns.count ? aligns[i] : .none {
                case .none: return ""
                case .left: return " align=\"left\""
                case .center: return " align=\"center\""
                case .right: return " align=\"right\""
                }
            }
            var out = "<table>\n<thead>\n<tr>\n"
            for (k, h) in header.enumerated() { out += "<th\(style(k))>\(inline.render(h))</th>\n" }
            out += "</tr>\n</thead>\n"
            if !rows.isEmpty {
                out += "<tbody>\n"
                for r in rows {
                    out += "<tr>\n"
                    for (k, c) in r.enumerated() { out += "<td\(style(k))>\(inline.render(c))</td>\n" }
                    out += "</tr>\n"
                }
                out += "</tbody>\n"
            }
            return out + "</table>\n"
        }
    }

    private func renderItem(_ item: MDListItem, tight: Bool) -> String {
        var cls = ""
        var box = ""
        if let c = item.checked {
            cls = " class=\"task-list-item\""
            box = "<input type=\"checkbox\" class=\"task-list-item-checkbox\" disabled\(c ? " checked" : "")> "
        }
        var inner = ""
        for (k, b) in item.blocks.enumerated() {
            if case let .paragraph(t) = b {
                let content = (k == 0 ? box : "") + inline.render(t)
                inner += tight ? content + "\n" : "<p>\(content)</p>\n"
                if k == 0 { box = "" }
            } else {
                inner += renderBlock(b, tight: tight)
            }
        }
        inner = box + inner
        while inner.hasSuffix("\n") { inner.removeLast() }
        return "<li\(cls)>\(inner)</li>\n"
    }

    /// GitHub-style heading anchor slug.
    func slug(_ text: String) -> String {
        var s = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                s.append(ch)
            } else if ch == " " {
                s.append("-")
            }
        }
        if let n = ctx.slugCounts[s] {
            ctx.slugCounts[s] = n + 1
            return "\(s)-\(n)"
        }
        ctx.slugCounts[s] = 1
        return s
    }
}

// MARK: - Inline parser

final class MDInline {
    let ctx: MDContext

    init(ctx: MDContext) { self.ctx = ctx }

    private final class Delim {
        let ch: Character
        var count: Int
        let canOpen: Bool
        let canClose: Bool
        var openTags: [String] = []
        var closeTags: [String] = []

        init(ch: Character, count: Int, canOpen: Bool, canClose: Bool) {
            self.ch = ch
            self.count = count
            self.canOpen = canOpen
            self.canClose = canClose
        }
    }

    private final class Bracket {
        let image: Bool
        let srcIndex: Int

        init(image: Bool, srcIndex: Int) {
            self.image = image
            self.srcIndex = srcIndex
        }
    }

    private enum Node {
        case text(String)
        case html(String)
        case delim(Delim)
        case bracket(Bracket)
    }

    private static let uriRegex = try! NSRegularExpression(pattern: #"^[A-Za-z][A-Za-z0-9+.\-]{1,31}:[^\s<>]*$"#)
    private static let emailRegex = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$"#)
    private static let tagRegex = try! NSRegularExpression(
        pattern: #"^(?:<[A-Za-z][A-Za-z0-9-]*(?:\s+[A-Za-z_:][A-Za-z0-9_.:-]*(?:\s*=\s*(?:[^\s"'=<>`]+|'[^']*'|"[^"]*"))?)*\s*/?>|</[A-Za-z][A-Za-z0-9-]*\s*>)$"#)

    static func normalizeLabel(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func isASCIIPunct(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return (33...47).contains(a) || (58...64).contains(a) || (91...96).contains(a) || (123...126).contains(a)
    }

    static func unescapePunct(_ s: String) -> String {
        guard s.utf8.contains(92), s.contains("\\") else { return s }
        var out = ""
        var it = Array(s)
        var i = 0
        while i < it.count {
            if it[i] == "\\", i + 1 < it.count, isASCIIPunct(it[i + 1]) {
                out.append(it[i + 1])
                i += 2
            } else {
                out.append(it[i])
                i += 1
            }
        }
        it.removeAll()
        return out
    }

    private static func isPunct(_ c: Character) -> Bool {
        isASCIIPunct(c) || c.isPunctuation || c.isSymbol
    }

    private func flanking(_ c: Character, _ before: Character?, _ after: Character?) -> (Bool, Bool) {
        let bWS = before.map { $0.isWhitespace } ?? true
        let aWS = after.map { $0.isWhitespace } ?? true
        let bP = before.map(Self.isPunct) ?? false
        let aP = after.map(Self.isPunct) ?? false
        let left = !aWS && (!aP || bWS || bP)
        let right = !bWS && (!bP || aWS || aP)
        if c == "_" {
            return (left && (!right || bP), right && (!left || aP))
        }
        return (left, right)
    }

    private static func hasInlineSyntax(_ s: String) -> Bool {
        var hasColon = false
        var hasDot = false
        for b in s.utf8 {
            switch b {
            case 92, 96, 42, 95, 126, 33, 91, 93, 60, 38, 10: // \ ` * _ ~ ! [ ] < & \n
                return true
            case 58: // :
                hasColon = true
            case 46: // .
                hasDot = true
            default:
                break
            }
        }
        if hasColon && s.contains("://") { return true }
        if hasDot && (s.contains("www.") || s.contains("WWW.")) { return true }
        return false
    }

    func render(_ s: String) -> String {
        if !Self.hasInlineSyntax(s) {
            return MDEscape.html(s)
        }
        let chars = Array(s)
        let n = chars.count
        var nodes: [Node] = []
        var text = ""
        var brackets: [Int] = []
        // Link openers at stack positions below this index are inactive (no links inside links).
        var inactiveBelow = 0
        // Code-span closers: start positions of every maximal backtick run, by run length, built on
        // first use. The scan position only moves forward, so a cursor per length makes each lookup
        // amortised O(1) (searching forward per opener was O(n·runs)).
        var backtickRuns: [Int: [Int]]?
        var backtickCursor: [Int: Int] = [:]
        func backtickClose(from: Int, len: Int) -> Int? {
            if backtickRuns == nil {
                var runs: [Int: [Int]] = [:]
                var k = 0
                while k < n {
                    if chars[k] == "`" {
                        let r = countRun(chars, k, "`")
                        runs[r, default: []].append(k)
                        k += r
                    } else {
                        k += 1
                    }
                }
                backtickRuns = runs
            }
            guard let list = backtickRuns?[len] else { return nil }
            var k = backtickCursor[len] ?? 0
            while k < list.count, list[k] < from { k += 1 }
            backtickCursor[len] = k
            return k < list.count ? list[k] : nil
        }
        // Start of the last "-->" in the text: an inline comment opened after it can never close,
        // so it is rejected without scanning (keeps many unclosed "<!--" linear).
        var lastCommentClose = -1
        if n >= 3 {
            var k = n - 3
            while k >= 0 {
                if chars[k] == "-", chars[k + 1] == "-", chars[k + 2] == ">" { lastCommentClose = k; break }
                k -= 1
            }
        }

        func flush() {
            if !text.isEmpty {
                nodes.append(.text(text))
                text = ""
            }
        }

        var i = 0
        while i < n {
            let c = chars[i]
            switch c {
            case "\\":
                if i + 1 < n {
                    let nx = chars[i + 1]
                    if nx == "\n" {
                        flush()
                        nodes.append(.html("<br>\n"))
                        i += 2
                        while i < n, chars[i] == " " { i += 1 }
                        continue
                    }
                    if Self.isASCIIPunct(nx) {
                        text.append(nx)
                        i += 2
                        continue
                    }
                }
                text.append(c)
                i += 1

            case "`":
                let run = countRun(chars, i, "`")
                if let end = backtickClose(from: i + run, len: run) {
                    var code = String(chars[(i + run)..<end]).replacingOccurrences(of: "\n", with: " ")
                    if code.count >= 2, code.first == " ", code.last == " ", code.contains(where: { $0 != " " }) {
                        code = String(code.dropFirst().dropLast())
                    }
                    flush()
                    nodes.append(.html("<code>\(MDEscape.html(code))</code>"))
                    i = end + run
                } else {
                    text.append(String(repeating: "`", count: run))
                    i += run
                }

            case "*", "_", "~":
                let run = countRun(chars, i, c)
                if c == "~" && run > 2 {
                    text.append(String(repeating: "~", count: run))
                    i += run
                    continue
                }
                let before: Character? = i > 0 ? chars[i - 1] : nil
                let after: Character? = i + run < n ? chars[i + run] : nil
                let (open, close) = flanking(c, before, after)
                flush()
                nodes.append(.delim(Delim(ch: c, count: run, canOpen: open, canClose: close)))
                i += run

            case "!":
                if i + 1 < n, chars[i + 1] == "[" {
                    flush()
                    brackets.append(nodes.count)
                    nodes.append(.bracket(Bracket(image: true, srcIndex: i + 2)))
                    i += 2
                } else {
                    text.append(c)
                    i += 1
                }

            case "[":
                if i + 1 < n, chars[i + 1] == "^", let close = indexOf("]", in: chars, from: i + 2) {
                    let id = String(chars[(i + 2)..<close]).lowercased()
                    if !id.isEmpty, !id.contains(where: { $0.isWhitespace }), ctx.footnoteDefs[id] != nil {
                        let num = ctx.footnoteNumber(id)
                        let attr = MDEscape.attr(id)
                        flush()
                        nodes.append(.html("<sup><a href=\"#fn-\(attr)\" id=\"fnref-\(attr)\" data-footnote-ref>\(num)</a></sup>"))
                        i = close + 1
                        continue
                    }
                }
                flush()
                brackets.append(nodes.count)
                nodes.append(.bracket(Bracket(image: false, srcIndex: i + 1)))
                i += 1

            case "]":
                guard let bi = brackets.last, case let .bracket(br) = nodes[bi] else {
                    text.append(c)
                    i += 1
                    continue
                }
                brackets.removeLast()
                let active = br.image || brackets.count >= inactiveBelow
                inactiveBelow = min(inactiveBelow, brackets.count)
                if !active {
                    nodes[bi] = .text(br.image ? "![" : "[")
                    text.append("]")
                    i += 1
                    continue
                }
                let label = String(chars[br.srcIndex..<i])
                var j = i + 1
                var dest: (url: String, title: String?)?
                if j < n, chars[j] == "(", let r = parseInlineLink(chars, j) {
                    dest = (r.url, r.title)
                    j = r.end
                } else if j < n, chars[j] == "[", let close = indexOf("]", in: chars, from: j + 1) {
                    let ref = String(chars[(j + 1)..<close])
                    if let d = ctx.refs[Self.normalizeLabel(ref.isEmpty ? label : ref)] {
                        dest = d
                        j = close + 1
                    }
                }
                if dest == nil, let d = ctx.refs[Self.normalizeLabel(label)] {
                    dest = d
                    j = i + 1
                }
                guard let (url, title) = dest else {
                    nodes[bi] = .text(br.image ? "![" : "[")
                    text.append("]")
                    i += 1
                    continue
                }
                flush()
                let inner = Array(nodes[(bi + 1)...])
                nodes.removeSubrange(bi...)
                let content = renderNodes(inner)
                let titleAttr = title.map { " title=\"\(MDEscape.attr($0))\"" } ?? ""
                if br.image {
                    let alt = MDEscape.plainText(content)
                    if MDEscape.isSafeResource(url, allowRemote: ctx.allowRemote) {
                        nodes.append(.html("<img src=\"\(MDEscape.url(url))\" alt=\"\(MDEscape.attr(alt))\"\(titleAttr)>"))
                    } else if !alt.isEmpty {
                        nodes.append(.text("[\(alt)]"))
                    }
                } else {
                    let href = MDEscape.isSafeLink(url) ? " href=\"\(MDEscape.url(url))\"" : ""
                    nodes.append(.html("<a\(href)\(titleAttr)>\(content)</a>"))
                    inactiveBelow = brackets.count
                }
                i = j

            case "<":
                if let (html, end) = parseAngle(chars, i, lastCommentClose: lastCommentClose) {
                    flush()
                    nodes.append(.html(html))
                    i = end
                } else {
                    text.append(c)
                    i += 1
                }

            case "&":
                if let end = entityEnd(chars, i) {
                    flush()
                    nodes.append(.html(String(chars[i..<end])))
                    i = end
                } else {
                    text.append(c)
                    i += 1
                }

            case "\n":
                var spaces = 0
                while text.hasSuffix(" ") {
                    text.removeLast()
                    spaces += 1
                }
                flush()
                nodes.append(.html(spaces >= 2 ? "<br>\n" : "\n"))
                i += 1
                while i < n, chars[i] == " " { i += 1 }

            case "h", "w", "H", "W":
                if i == 0 || isAutolinkBoundary(chars[i - 1]), let (url, end) = extendedAutolink(chars, i) {
                    flush()
                    let href = url.lowercased().hasPrefix("www.") ? "http://" + url : url
                    nodes.append(.html(MDEscape.isSafeLink(href)
                        ? "<a href=\"\(MDEscape.url(href))\">\(MDEscape.html(url))</a>" : MDEscape.html(url)))
                    i = end
                } else {
                    text.append(c)
                    i += 1
                }

            default:
                text.append(c)
                i += 1
            }
        }
        flush()
        for k in brackets {
            if case let .bracket(b) = nodes[k] { nodes[k] = .text(b.image ? "![" : "[") }
        }
        return renderNodes(nodes)
    }

    /// Resolves emphasis delimiters (CommonMark algorithm) and serialises nodes to HTML.
    private func renderNodes(_ nodes: [Node]) -> String {
        let active: [Int] = nodes.indices.filter {
            if case .delim = nodes[$0] { return true }
            return false
        }
        // The delimiter stack is a doubly linked list over positions in `active`: removing the
        // delimiters between a matched opener and closer is O(1) (array removal made it O(n²)).
        let m = active.count
        var prev = Array(-1..<(m - 1))
        var next = Array(1..<(m + 1))
        func unlink(_ p: Int) {
            if prev[p] >= 0 { next[prev[p]] = next[p] }
            if next[p] < m { prev[next[p]] = prev[p] }
        }
        // CommonMark "openers_bottom": once a closer of a given kind finds no opener, later closers of
        // the same kind never search below that point again. Keeps matching linear.
        var openersBottom: [String: Int] = [:]
        var ci = m > 0 ? 0 : m
        while ci < m {
            guard case let .delim(closer) = nodes[active[ci]], closer.canClose, closer.count > 0 else {
                ci = next[ci]
                continue
            }
            let key = "\(closer.ch)\(closer.canOpen ? 1 : 0)\(closer.ch == "~" ? closer.count : closer.count % 3)"
            let bottom = openersBottom[key] ?? -1
            var found = false
            var oi = prev[ci]
            while oi >= 0, oi > bottom {
                if case let .delim(opener) = nodes[active[oi]], opener.ch == closer.ch, opener.canOpen, opener.count > 0 {
                    if closer.ch == "~" {
                        if opener.count != closer.count { oi = prev[oi]; continue }
                    } else if (opener.canClose || closer.canOpen) && (opener.count + closer.count) % 3 == 0
                                && !(opener.count % 3 == 0 && closer.count % 3 == 0) {
                        oi = prev[oi]
                        continue
                    }
                    found = true
                    let use: Int
                    let tag: String
                    if closer.ch == "~" {
                        use = closer.count
                        tag = "del"
                    } else {
                        use = opener.count >= 2 && closer.count >= 2 ? 2 : 1
                        tag = use == 2 ? "strong" : "em"
                    }
                    opener.count -= use
                    closer.count -= use
                    opener.openTags.insert("<\(tag)>", at: 0)
                    closer.closeTags.append("</\(tag)>")
                    // Delimiters between opener and closer can no longer match.
                    next[oi] = ci
                    prev[ci] = oi
                    if opener.count == 0 { unlink(oi) }
                    break
                }
                oi = prev[oi]
            }
            if !found {
                openersBottom[key] = prev[ci]
                ci = next[ci]
            } else if closer.count == 0 {
                let n = next[ci]
                unlink(ci)
                ci = n
            }
        }

        var out = ""
        for node in nodes {
            switch node {
            case let .text(t): out += MDEscape.html(t)
            case let .html(h): out += h
            case let .delim(d): out += d.closeTags.joined() + String(repeating: d.ch, count: d.count) + d.openTags.joined()
            case let .bracket(b): out += b.image ? "![" : "["
            }
        }
        return out
    }

    // MARK: Helpers

    private func countRun(_ c: [Character], _ i: Int, _ ch: Character) -> Int {
        var j = i
        while j < c.count, c[j] == ch { j += 1 }
        return j - i
    }

    private func indexOf(_ ch: Character, in c: [Character], from: Int) -> Int? {
        var j = from
        while j < c.count {
            if c[j] == "\\" { j += 2; continue }
            if c[j] == ch { return j }
            if c[j] == "[" && ch == "]" { return nil }
            j += 1
        }
        return nil
    }

    private func parseInlineLink(_ c: [Character], _ start: Int) -> (url: String, title: String?, end: Int)? {
        let n = c.count
        var p = start + 1
        func skipWS() { while p < n, c[p] == " " || c[p] == "\t" || c[p] == "\n" { p += 1 } }
        skipWS()
        var url = ""
        if p < n, c[p] == "<" {
            p += 1
            while p < n, c[p] != ">", c[p] != "\n" {
                if c[p] == "\\", p + 1 < n, Self.isASCIIPunct(c[p + 1]) {
                    url.append(c[p + 1])
                    p += 2
                    continue
                }
                url.append(c[p])
                p += 1
            }
            guard p < n, c[p] == ">" else { return nil }
            p += 1
        } else {
            var depth = 0
            while p < n {
                let ch = c[p]
                if ch.isWhitespace { break }
                if ch == "\\", p + 1 < n, Self.isASCIIPunct(c[p + 1]) {
                    url.append(c[p + 1])
                    p += 2
                    continue
                }
                if ch == "(" {
                    depth += 1
                    if depth > 32 { return nil } // CommonMark nesting limit; keeps each attempt O(1)
                } else if ch == ")" {
                    if depth == 0 { break }
                    depth -= 1
                }
                url.append(ch)
                p += 1
            }
        }
        let beforeTitle = p
        skipWS()
        var title: String?
        if p < n, p > beforeTitle, c[p] == "\"" || c[p] == "'" || c[p] == "(" {
            let close: Character = c[p] == "(" ? ")" : c[p]
            var t = ""
            p += 1
            while p < n, c[p] != close {
                if c[p] == "\\", p + 1 < n, Self.isASCIIPunct(c[p + 1]) {
                    t.append(c[p + 1])
                    p += 2
                    continue
                }
                t.append(c[p])
                p += 1
            }
            guard p < n else { return nil }
            p += 1
            title = t
            skipWS()
        }
        guard p < n, c[p] == ")" else { return nil }
        return (url, title, p + 1)
    }

    private func parseAngle(_ c: [Character], _ i: Int, lastCommentClose: Int) -> (String, Int)? {
        let n = c.count
        // HTML comment: consumed and dropped (not rendered, as on GitHub).
        if i + 3 < n, c[i + 1] == "!", c[i + 2] == "-", c[i + 3] == "-" {
            guard i + 4 <= lastCommentClose else { return nil }
            var j = i + 4
            while j + 2 < n {
                if c[j] == "-", c[j + 1] == "-", c[j + 2] == ">" {
                    return ("", j + 3)
                }
                j += 1
            }
            return nil
        }
        var close: Int?
        var j = i + 1
        var quote: Character?
        while j < n, j - i < 512 {
            let ch = c[j]
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == ">" {
                close = j
                break
            } else if ch == "<" {
                break
            }
            j += 1
        }
        guard let end = close else { return nil }
        let inner = String(c[(i + 1)..<end])
        let ns = inner as NSString
        let r = NSRange(location: 0, length: ns.length)
        if !inner.contains(" "), Self.uriRegex.firstMatch(in: inner, range: r) != nil {
            guard MDEscape.isSafeLink(inner) else { return nil } // e.g. <javascript:…> stays text
            return ("<a href=\"\(MDEscape.url(inner))\">\(MDEscape.html(inner))</a>", end + 1)
        }
        if Self.emailRegex.firstMatch(in: inner, range: r) != nil {
            return ("<a href=\"mailto:\(MDEscape.url(inner))\">\(MDEscape.html(inner))</a>", end + 1)
        }
        let full = String(c[i...end])
        let fns = full as NSString
        if Self.tagRegex.firstMatch(in: full, range: NSRange(location: 0, length: fns.length)) != nil {
            ctx.rawHTMLCount += 1
            return (HTMLSanitizer.sanitize(full, allowRemote: ctx.allowRemote), end + 1)
        }
        return nil
    }

    private func entityEnd(_ c: [Character], _ i: Int) -> Int? {
        var j = i + 1
        let n = c.count
        guard j < n else { return nil }
        if c[j] == "#" {
            j += 1
            var hex = false
            if j < n, c[j] == "x" || c[j] == "X" {
                hex = true
                j += 1
            }
            let s = j
            while j < n, j - s < 7, (hex ? c[j].isHexDigit : (c[j].isASCII && c[j].isNumber)) { j += 1 }
            guard j > s, j < n, c[j] == ";" else { return nil }
            return j + 1
        }
        let s = j
        while j < n, j - s < 32, c[j].isASCII, c[j].isLetter || c[j].isNumber { j += 1 }
        guard j > s, j < n, c[j] == ";", c[s].isLetter else { return nil }
        return j + 1
    }

    private func isAutolinkBoundary(_ c: Character) -> Bool {
        c.isWhitespace || c == "*" || c == "_" || c == "~" || c == "("
    }

    private func extendedAutolink(_ c: [Character], _ i: Int) -> (String, Int)? {
        let head = String(c[i..<min(c.count, i + 8)]).lowercased()
        let prefixLen: Int
        if head.hasPrefix("https://") {
            prefixLen = 8
        } else if head.hasPrefix("http://") {
            prefixLen = 7
        } else if head.hasPrefix("www.") {
            prefixLen = 4
        } else {
            return nil
        }
        var p = i
        while p < c.count, !c[p].isWhitespace, c[p] != "<" { p += 1 }
        var url = String(c[i..<p])
        // Counted once and updated while trimming (re-counting per character was O(n²)).
        let opens = url.filter { $0 == "(" }.count
        var closes = url.filter { $0 == ")" }.count
        while let last = url.last {
            if "?!.,:*_~'\"".contains(last) {
                url.removeLast()
                continue
            }
            if last == ")", closes > opens {
                url.removeLast()
                closes -= 1
                continue
            }
            break
        }
        guard url.count > prefixLen else { return nil }
        if prefixLen == 4 && !url.dropFirst(4).contains(".") { return nil }
        return (url, i + url.count)
    }
}

// MARK: - Escaping

enum MDEscape {
    static func html(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }

    static func attr(_ s: String) -> String { html(s) }

    /// Link/image URL checks for Markdown syntax (`[x](…)`, `![x](…)`, autolinks). Checked both
    /// as written and with character references decoded.
    static func isSafeLink(_ url: String) -> Bool {
        HTMLSanitizer.isSafeLink(url) && HTMLSanitizer.isSafeLink(HTMLSanitizer.decodeEntities(url))
    }

    static func isSafeResource(_ url: String, allowRemote: Bool) -> Bool {
        HTMLSanitizer.isSafeResource(url, allowRemote: allowRemote)
            && HTMLSanitizer.isSafeResource(HTMLSanitizer.decodeEntities(url), allowRemote: allowRemote)
    }

    static func url(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:/?#[]@!$&'()*+,;=%")
        var out = ""
        for scalar in s.unicodeScalars {
            if allowed.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else {
                for b in String(scalar).utf8 { out += String(format: "%%%02X", b) }
            }
        }
        return html(out)
    }

    private static let tagStrip = try! NSRegularExpression(pattern: "<[^>]*>")

    static func plainText(_ html: String) -> String {
        let ns = html as NSString
        let stripped = tagStrip.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return stripped
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

enum MDAlertIcons {
    static func svg(_ kind: String) -> String {
        let path: String
        switch kind {
        case "tip":
            path = "M8 1.5a4.5 4.5 0 0 0-2.7 8.1c.4.3.7.8.7 1.4v.5h4v-.5c0-.6.3-1.1.7-1.4A4.5 4.5 0 0 0 8 1.5ZM6 13.5h4v1H6z"
        case "important":
            path = "M1.5 2.5h13v9h-7l-3 3v-3h-3zM7.25 4.5h1.5v3.5h-1.5zm0 4.5h1.5v1.5h-1.5z"
        case "warning":
            path = "M8 1 15.5 14.5H.5zM7.25 6v4h1.5V6zm0 5v1.5h1.5V11z"
        case "caution":
            path = "M5 1h6l4 4v6l-4 4H5l-4-4V5zm2.25 3.5v4.5h1.5V4.5zm0 6v1.5h1.5v-1.5z"
        default:
            path = "M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1Zm-.75 3.5h1.5V6h-1.5zm0 3h1.5v4h-1.5z"
        }
        return "<svg viewBox=\"0 0 16 16\" width=\"16\" height=\"16\" aria-hidden=\"true\"><path fill-rule=\"evenodd\" d=\"\(path)\"></path></svg>"
    }
}
