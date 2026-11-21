import Foundation

/// A single text replacement plus the selection to apply afterwards (UTF-16 ranges).
struct TextEdit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange
}

enum FormatOp: Equatable {
    case wrap(prefix: String, suffix: String, placeholder: String)
    case heading(Int) // 0 = normal paragraph
    case bulletList
    case numberedList
    case taskList
    case blockquote
    case indent
    case outdent
    case codeBlock
    case link
    case image
    case comment
    case table
    case horizontalRule
    case clearFormatting
    case newParagraph
}

/// Pure Markdown editing operations: (text, selection) → TextEdit.
enum MarkdownFormatter {
    static func edit(for op: FormatOp, in text: NSString, selection: NSRange) -> TextEdit? {
        let sel = clamp(selection, text)
        switch op {
        case let .wrap(p, s, ph): return wrap(text, sel, p, s, placeholder: ph)
        case let .heading(level): return heading(text, sel, level)
        case .bulletList: return list(text, sel, kind: .bullet)
        case .numberedList: return list(text, sel, kind: .numbered)
        case .taskList: return list(text, sel, kind: .task)
        case .blockquote: return blockquote(text, sel)
        case .indent: return applyLines(text, sel) { $0.map { MDLine.isBlank($0) ? $0 : "    " + $0 } }
        case .outdent: return applyLines(text, sel) { $0.map(outdentLine) }
        case .codeBlock: return codeBlock(text, sel)
        case .link: return link(text, sel, image: false)
        case .image: return link(text, sel, image: true)
        case .comment: return comment(text, sel)
        case .table: return insertBlock(text, sel, block: tableTemplate, selectFirst: "Column 1")
        case .horizontalRule: return insertBlock(text, sel, block: "---", selectFirst: nil)
        case .clearFormatting: return clearFormatting(text, sel)
        case .newParagraph: return newParagraph(text, sel)
        }
    }

    static let tableTemplate = """
    | Column 1 | Column 2 | Column 3 |
    | -------- | -------- | -------- |
    | Cell     | Cell     | Cell     |
    """

    // MARK: - Line decomposition

    struct LineParts {
        var indent: String
        var quote: String
        var marker: String
        var heading: String
        var content: String

        var joined: String { indent + quote + marker + heading + content }

        var isBullet: Bool { !marker.isEmpty && !isNumbered && !isTask }
        var isNumbered: Bool { marker.trimmingCharacters(in: .whitespaces).first?.isNumber ?? false }
        var isTask: Bool { marker.contains("[") }
    }

    private static let partsRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)((?:>[ ]?)*)([ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)?(#{1,6}(?:[ \t]+|$))?(.*)$"#)

    static func decompose(_ line: String) -> LineParts {
        let ns = line as NSString
        guard let m = partsRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return LineParts(indent: "", quote: "", marker: "", heading: "", content: line)
        }
        func g(_ i: Int) -> String {
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
        var parts = LineParts(indent: g(1), quote: g(2), marker: g(3), heading: g(4), content: g(5))
        // A list marker made only of "-"/"*" with nothing after is not a list (e.g. thematic break "---").
        if !parts.marker.isEmpty, parts.content.isEmpty, parts.heading.isEmpty,
           parts.marker.trimmingCharacters(in: .whitespaces).count == 1, line.trimmingCharacters(in: .whitespaces).count > 1,
           MDBlockParser(ctx: MDContext()).isRule(line) {
            parts.marker = ""
            parts.content = String(line.dropFirst(parts.indent.count + parts.quote.count))
        }
        return parts
    }

    // MARK: - Helpers

    private static func clamp(_ r: NSRange, _ text: NSString) -> NSRange {
        let loc = min(max(0, r.location), text.length)
        return NSRange(location: loc, length: min(r.length, text.length - loc))
    }

    /// Range of complete lines touched by the selection (without trailing newline) and their contents.
    static func lineBlock(_ text: NSString, _ sel: NSRange) -> (NSRange, [String]) {
        var r = sel
        if r.length > 0, text.character(at: NSMaxRange(r) - 1) == 10 { r.length -= 1 }
        var lr = text.lineRange(for: r)
        if lr.length > 0, text.character(at: NSMaxRange(lr) - 1) == 10 { lr.length -= 1 }
        return (lr, text.substring(with: lr).components(separatedBy: "\n"))
    }

    static func applyLines(_ text: NSString, _ sel: NSRange, _ transform: ([String]) -> [String]) -> TextEdit? {
        let (lr, lines) = lineBlock(text, sel)
        let newLines = transform(lines)
        let rep = newLines.joined(separator: "\n")
        if rep == text.substring(with: lr) { return nil }
        let newSel: NSRange
        if sel.length == 0 && lines.count == 1 {
            let fromEnd = NSMaxRange(lr) - sel.location
            let newLen = (rep as NSString).length
            newSel = NSRange(location: max(lr.location, lr.location + newLen - fromEnd), length: 0)
        } else {
            newSel = NSRange(location: lr.location, length: (rep as NSString).length)
        }
        return TextEdit(range: lr, replacement: rep, selection: newSel)
    }

    private static func outdentLine(_ line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        var n = 0
        for c in line {
            if c == " " && n < 4 { n += 1 } else { break }
        }
        return String(line.dropFirst(n))
    }

    static func wordRange(_ text: NSString, at loc: Int) -> NSRange {
        let isWord: (unichar) -> Bool = { c in
            guard let s = Unicode.Scalar(c) else { return true } // surrogate halves: treat as word
            return CharacterSet.alphanumerics.contains(s)
        }
        var start = loc
        while start > 0, isWord(text.character(at: start - 1)) { start -= 1 }
        var end = loc
        while end < text.length, isWord(text.character(at: end)) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func substring(_ text: NSString, _ loc: Int, _ len: Int) -> String? {
        guard loc >= 0, len >= 0, loc + len <= text.length else { return nil }
        return text.substring(with: NSRange(location: loc, length: len))
    }

    // MARK: - Inline wrapping

    static func wrap(_ text: NSString, _ selection: NSRange, _ pre: String, _ suf: String, placeholder: String) -> TextEdit {
        var r = selection
        let pl = (pre as NSString).length
        let sl = (suf as NSString).length

        if r.length == 0 {
            let w = wordRange(text, at: r.location)
            if w.length > 0 { r = w }
        } else {
            // Trim surrounding whitespace from the selection.
            while r.length > 0, let s = Unicode.Scalar(text.character(at: r.location)), CharacterSet.whitespacesAndNewlines.contains(s) {
                r.location += 1
                r.length -= 1
            }
            while r.length > 0, let s = Unicode.Scalar(text.character(at: NSMaxRange(r) - 1)), CharacterSet.whitespacesAndNewlines.contains(s) {
                r.length -= 1
            }
        }

        // Selection already contains the markers → unwrap.
        if r.length >= pl + sl {
            let selected = text.substring(with: r) as NSString
            if selected.hasPrefix(pre) && selected.hasSuffix(suf) && !isPartOfLongerRun(selected as String, pre) {
                let inner = selected.substring(with: NSRange(location: pl, length: selected.length - pl - sl))
                return TextEdit(range: r, replacement: inner, selection: NSRange(location: r.location, length: (inner as NSString).length))
            }
        }
        // Markers directly around the selection → unwrap.
        if let before = substring(text, r.location - pl, pl), before == pre,
           let after = substring(text, NSMaxRange(r), sl), after == suf,
           !isDifferentEmphasis(text, r, pre) {
            let full = NSRange(location: r.location - pl, length: r.length + pl + sl)
            return TextEdit(range: full, replacement: text.substring(with: r), selection: NSRange(location: full.location, length: r.length))
        }
        if r.length == 0 {
            let ins = pre + placeholder + suf
            return TextEdit(range: r, replacement: ins,
                            selection: NSRange(location: r.location + pl, length: (placeholder as NSString).length))
        }
        let inner = text.substring(with: r)
        return TextEdit(range: r, replacement: pre + inner + suf, selection: NSRange(location: r.location + pl, length: r.length))
    }

    /// `*` inside `**bold**` is not italic.
    private static func isPartOfLongerRun(_ s: String, _ pre: String) -> Bool {
        guard pre == "*" || pre == "_" else { return false }
        let c = pre.first!
        let lead = s.prefix(while: { $0 == c }).count
        let trail = s.reversed().prefix(while: { $0 == c }).count
        return lead == 2 && trail == 2
    }

    /// When unwrapping italic `*`, make sure the surrounding run isn't exactly `**` (bold).
    private static func isDifferentEmphasis(_ text: NSString, _ r: NSRange, _ pre: String) -> Bool {
        guard pre == "*" || pre == "_" else { return false }
        let c = (pre as NSString).character(at: 0)
        var lead = 0
        var i = r.location - 1
        while i >= 0, text.character(at: i) == c { lead += 1; i -= 1 }
        var trail = 0
        var j = NSMaxRange(r)
        while j < text.length, text.character(at: j) == c { trail += 1; j += 1 }
        return lead == 2 && trail == 2
    }

    // MARK: - Block operations

    static func heading(_ text: NSString, _ sel: NSRange, _ level: Int) -> TextEdit? {
        applyLines(text, sel) { lines in
            lines.map { line in
                if MDLine.isBlank(line) && lines.count > 1 { return line }
                var p = decompose(line)
                p.marker = ""
                p.heading = level > 0 ? String(repeating: "#", count: level) + " " : ""
                return p.joined
            }
        }
    }

    enum ListKind { case bullet, numbered, task }

    static func list(_ text: NSString, _ sel: NSRange, kind: ListKind) -> TextEdit? {
        applyLines(text, sel) { lines in
            let parts = lines.map(decompose)
            let nonBlank = parts.enumerated().filter { !MDLine.isBlank(lines[$0.offset]) }.map { $0.element }
            let allMatch = !nonBlank.isEmpty && nonBlank.allSatisfy {
                switch kind {
                case .bullet: return $0.isBullet
                case .numbered: return $0.isNumbered && !$0.isTask
                case .task: return $0.isTask
                }
            }
            var counters: [String: Int] = [:]
            return parts.enumerated().map { idx, p0 in
                var p = p0
                if MDLine.isBlank(lines[idx]) && lines.count > 1 { return lines[idx] }
                if allMatch {
                    p.marker = ""
                    return p.joined
                }
                p.heading = ""
                switch kind {
                case .bullet: p.marker = "- "
                case .task: p.marker = "- [ ] "
                case .numbered:
                    let n = (counters[p.indent] ?? 0) + 1
                    counters[p.indent] = n
                    p.marker = "\(n). "
                }
                return p.joined
            }
        }
    }

    static func blockquote(_ text: NSString, _ sel: NSRange) -> TextEdit? {
        applyLines(text, sel) { lines in
            let parts = lines.map(decompose)
            let allQuoted = parts.allSatisfy { !$0.quote.isEmpty }
            return parts.map { p0 in
                var p = p0
                if allQuoted {
                    var q = Substring(p.quote)
                    if q.hasPrefix(">") { q = q.dropFirst() }
                    if q.hasPrefix(" ") { q = q.dropFirst() }
                    p.quote = String(q)
                } else {
                    p.quote = "> " + p.quote
                }
                return p.joined
            }
        }
    }

    static func codeBlock(_ text: NSString, _ sel: NSRange) -> TextEdit? {
        let (lr, lines) = lineBlock(text, sel)
        if lines.count >= 2, lines.first!.trimmingCharacters(in: .whitespaces).hasPrefix("```"),
           lines.last!.trimmingCharacters(in: .whitespaces) == "```" {
            let inner = lines.dropFirst().dropLast().joined(separator: "\n")
            return TextEdit(range: lr, replacement: inner, selection: NSRange(location: lr.location, length: (inner as NSString).length))
        }
        let body = lines.joined(separator: "\n")
        if sel.length == 0 && MDLine.isBlank(body) {
            let rep = "```\n\n```"
            return TextEdit(range: lr, replacement: rep, selection: NSRange(location: lr.location + 4, length: 0))
        }
        let rep = "```\n" + body + "\n```"
        // Caret after the opening fence so the language can be typed.
        return TextEdit(range: lr, replacement: rep, selection: NSRange(location: lr.location + 3, length: 0))
    }

    static func link(_ text: NSString, _ sel: NSRange, image: Bool) -> TextEdit {
        let selected = text.substring(with: sel)
        let bang = image ? "!" : ""
        let isURL = selected.range(of: #"^(https?://|www\.|mailto:)\S+$"#, options: .regularExpression) != nil
        if isURL {
            let label = image ? "alt text" : "link text"
            let rep = "\(bang)[\(label)](\(selected))"
            return TextEdit(range: sel, replacement: rep,
                            selection: NSRange(location: sel.location + (bang as NSString).length + 1, length: (label as NSString).length))
        }
        let label = selected.isEmpty ? (image ? "alt text" : "link text") : selected
        let rep = "\(bang)[\(label)](url)"
        let labelLen = (label as NSString).length
        if selected.isEmpty {
            return TextEdit(range: sel, replacement: rep,
                            selection: NSRange(location: sel.location + (bang as NSString).length + 1, length: labelLen))
        }
        let urlLoc = sel.location + (bang as NSString).length + 1 + labelLen + 2
        return TextEdit(range: sel, replacement: rep, selection: NSRange(location: urlLoc, length: 3))
    }

    static func comment(_ text: NSString, _ sel: NSRange) -> TextEdit {
        var r = sel
        if r.length == 0 {
            let (lr, lines) = lineBlock(text, sel)
            if let line = lines.first, !MDLine.isBlank(line) {
                let lead = (line as NSString).length - (MDLine.trimLeading(line) as NSString).length
                r = NSRange(location: lr.location + lead, length: lr.length - lead)
            }
        }
        return wrap(text, r, "<!-- ", " -->", placeholder: "comment")
    }

    static func insertBlock(_ text: NSString, _ sel: NSRange, block: String, selectFirst: String?) -> TextEdit {
        let lineRange = text.lineRange(for: NSRange(location: sel.location, length: 0))
        var contentEnd = NSMaxRange(lineRange)
        if contentEnd > lineRange.location, text.character(at: contentEnd - 1) == 10 { contentEnd -= 1 }
        let line = text.substring(with: NSRange(location: lineRange.location, length: contentEnd - lineRange.location))
        let blockLen = (block as NSString).length
        if MDLine.isBlank(line) {
            let range = NSRange(location: lineRange.location, length: contentEnd - lineRange.location)
            let needsLeadingBlank = lineRange.location >= 2 && text.character(at: lineRange.location - 2) != 10
            let lead = needsLeadingBlank ? "\n" : ""
            let rep = lead + block + "\n"
            let base = range.location + (lead as NSString).length
            let selRange = selectFirst.map { NSRange(location: base + 2, length: ($0 as NSString).length) }
                ?? NSRange(location: base + blockLen + 1, length: 0)
            return TextEdit(range: range, replacement: rep, selection: selRange)
        }
        let rep = "\n\n" + block + "\n"
        let base = contentEnd + 2
        let selRange = selectFirst.map { NSRange(location: base + 2, length: ($0 as NSString).length) }
            ?? NSRange(location: base + blockLen + 1, length: 0)
        return TextEdit(range: NSRange(location: contentEnd, length: 0), replacement: rep, selection: selRange)
    }

    private static let clearPatterns: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: #"</?(?:ins|u|sup|sub|mark|b|i|strong|em|del|s|code)>"#, options: .caseInsensitive), ""),
        (try! NSRegularExpression(pattern: #"<!--\s?|\s?-->"#), ""),
        // Content never runs past the next opener of the same kind (keeps each pattern linear).
        (try! NSRegularExpression(pattern: #"\*\*(?=\S)((?:[^*\n]|\*(?!\*))+?)(?<=\S)\*\*"#), "$1"),
        (try! NSRegularExpression(pattern: #"__(?=\S)((?:[^_\n]|_(?!_))+?)(?<=\S)__"#), "$1"),
        (try! NSRegularExpression(pattern: #"~~(?=\S)((?:[^~\n]|~(?!~))+?)(?<=\S)~~"#), "$1"),
        (try! NSRegularExpression(pattern: #"(?<![\\\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#), "$1"),
        (try! NSRegularExpression(pattern: #"(?<![\\\w_])_(?=\S)([^_\n]+?)(?<=\S)_(?![\w_])"#), "$1"),
        (try! NSRegularExpression(pattern: #"(`+)(.+?)\1"#), "$2"),
    ]

    static func clearFormatting(_ text: NSString, _ sel: NSRange) -> TextEdit? {
        var r = sel
        if r.length == 0 { r = lineBlock(text, sel).0 }
        var s = text.substring(with: r)
        for (re, tpl) in clearPatterns {
            s = re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: tpl)
        }
        if s == text.substring(with: r) { return nil }
        return TextEdit(range: r, replacement: s, selection: NSRange(location: r.location, length: (s as NSString).length))
    }

    static func newParagraph(_ text: NSString, _ sel: NSRange) -> TextEdit {
        let lr = text.lineRange(for: NSRange(location: NSMaxRange(sel), length: 0))
        var end = NSMaxRange(lr)
        if end > lr.location, text.character(at: end - 1) == 10 { end -= 1 }
        return TextEdit(range: NSRange(location: end, length: 0), replacement: "\n\n", selection: NSRange(location: end + 2, length: 0))
    }

    // MARK: - Typing helpers

    /// Called on Return: continues lists/quotes, or ends them on an empty item.
    static func continueList(text: NSString, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let lr = text.lineRange(for: NSRange(location: selection.location, length: 0))
        var end = NSMaxRange(lr)
        if end > lr.location, text.character(at: end - 1) == 10 { end -= 1 }
        let line = text.substring(with: NSRange(location: lr.location, length: end - lr.location))
        let p = decompose(line)
        guard !p.marker.isEmpty || !p.quote.isEmpty else { return nil }
        let prefixLen = ((p.indent + p.quote + p.marker) as NSString).length
        guard selection.location - lr.location >= prefixLen else { return nil }
        if isInsideFence(text, before: lr.location) { return nil }

        if p.content.trimmingCharacters(in: .whitespaces).isEmpty && p.heading.isEmpty {
            // Empty item: end the list (or one quote level).
            let newLine = p.marker.isEmpty ? p.indent : p.indent + p.quote
            return TextEdit(range: NSRange(location: lr.location, length: end - lr.location), replacement: newLine,
                            selection: NSRange(location: lr.location + (newLine as NSString).length, length: 0))
        }
        var next = p.indent + p.quote
        if !p.marker.isEmpty { next += nextMarker(p.marker) }
        let ins = "\n" + next
        return TextEdit(range: selection, replacement: ins, selection: NSRange(location: selection.location + (ins as NSString).length, length: 0))
    }

    private static let orderedMarker = try! NSRegularExpression(pattern: #"^([ \t]*)(\d+)([.)])([ \t]+)(\[[ xX]\][ \t]+)?$"#)

    static func nextMarker(_ marker: String) -> String {
        let ns = marker as NSString
        if let m = orderedMarker.firstMatch(in: marker, range: NSRange(location: 0, length: ns.length)) {
            let n = (Int(ns.substring(with: m.range(at: 2))) ?? 0) + 1
            let task = m.range(at: 5).location != NSNotFound ? "[ ] " : ""
            return ns.substring(with: m.range(at: 1)) + "\(n)" + ns.substring(with: m.range(at: 3)) + ns.substring(with: m.range(at: 4)) + task
        }
        return marker.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
    }

    static func isInsideFence(_ text: NSString, before loc: Int) -> Bool {
        var inFence = false
        text.substring(to: loc).enumerateLines { line, _ in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { inFence.toggle() }
        }
        return inFence
    }

    static func isListLine(_ text: NSString, _ sel: NSRange) -> Bool {
        let (_, lines) = lineBlock(text, sel)
        return lines.allSatisfy { !decompose($0).marker.isEmpty }
    }
}
