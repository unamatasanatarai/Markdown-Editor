import Foundation

/// Allow-list sanitizer for the raw HTML that Markdown documents may contain, in the spirit of
/// GitHub's: formatting tags survive (`<details>`, `<kbd>`, `<sup>`, `<img width>`, `<p align>`…),
/// while scripts, event handlers, styles, frames, forms, SVG, `<base>`/`<meta>`/`<link>` and
/// non-web URL schemes are removed.
///
/// Every tag is re-serialised from parsed parts, so attribute values are decoded once and
/// re-escaped: obfuscations such as `&#104;ttp:` or `java&#9;script:` are checked in decoded form.
/// With `allowRemote == false` (rich-text conversion, Quick Look) no attribute may reference a
/// remote resource, which makes the result safe to hand to loaders that fetch subresources.
enum HTMLSanitizer {
    static let allowedTags: Set<String> = [
        "a", "abbr", "acronym", "b", "bdi", "bdo", "big", "blockquote", "br", "caption", "center", "cite",
        "code", "col", "colgroup", "dd", "del", "details", "dfn", "div", "dl", "dt", "em", "figcaption",
        "figure", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "img", "ins", "kbd", "li", "mark", "ol",
        "p", "picture", "pre", "q", "rp", "rt", "ruby", "s", "samp", "small", "source", "span", "strike",
        "strong", "sub", "summary", "sup", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "tt",
        "u", "ul", "var", "wbr",
    ]
    /// Removed together with everything up to their closing tag (within the same fragment).
    static let dropWithContent: Set<String> = [
        "script", "style", "textarea", "title", "iframe", "object", "embed", "noscript", "template",
        "svg", "math", "select", "xmp", "noembed", "noframes", "plaintext", "frameset", "applet",
    ]
    static let globalAttributes: Set<String> = [
        "align", "alt", "title", "dir", "lang", "width", "height", "valign", "abbr", "headers", "scope",
        "colspan", "rowspan", "span", "start", "reversed", "open", "datetime", "id", "name", "summary",
        "hspace", "vspace", "border", "cellpadding", "cellspacing", "nowrap", "char", "charoff", "type",
    ]
    static let urlAttributes: [String: Set<String>] = [
        "a": ["href"],
        "img": ["src", "srcset"],
        "source": ["src", "srcset", "media"],
    ]

    // MARK: Fragments

    /// Sanitizes an HTML fragment (a raw HTML block or a single inline tag).
    static func sanitize(_ html: String, allowRemote: Bool) -> String {
        let c = Array(html)
        let n = c.count
        var out = ""
        var dropUntil: String?
        var i = 0
        while i < n {
            if c[i] == "<" {
                if i + 3 < n, c[i + 1] == "!", c[i + 2] == "-", c[i + 3] == "-" {
                    i = find("-->", in: c, from: i + 4).map { $0 + 3 } ?? n // comments are dropped
                    continue
                }
                if i + 1 < n, c[i + 1] == "!" || c[i + 1] == "?" {
                    i = (find(">", in: c, from: i + 2) ?? n - 1) + 1 // doctype / processing instruction
                    continue
                }
                if let (tag, end) = parseTag(c, i) {
                    i = end
                    if let d = dropUntil {
                        if tag.closing && tag.name == d { dropUntil = nil }
                        continue
                    }
                    if dropWithContent.contains(tag.name) {
                        if !tag.closing && !tag.selfClosing { dropUntil = tag.name }
                        continue
                    }
                    out += render(tag, allowRemote: allowRemote)
                    continue
                }
                if dropUntil == nil { out += "&lt;" }
                i += 1
                continue
            }
            if dropUntil == nil { out.append(c[i]) }
            i += 1
        }
        return out
    }

    private static func find(_ needle: String, in c: [Character], from: Int) -> Int? {
        let nd = Array(needle)
        var j = from
        while j + nd.count <= c.count {
            if c[j] == nd[0] {
                var k = 1
                while k < nd.count, c[j + k] == nd[k] { k += 1 }
                if k == nd.count { return j }
            }
            j += 1
        }
        return nil
    }

    // MARK: Tags

    struct Tag {
        var name: String
        var closing: Bool
        var selfClosing: Bool
        var attributes: [(name: String, value: String)] // values decoded
    }

    /// Parses a tag starting at `c[i] == "<"`. Returns nil when it is not a well-formed tag
    /// (the `<` is then treated as text).
    static func parseTag(_ c: [Character], _ start: Int) -> (Tag, Int)? {
        let n = c.count
        var j = start + 1
        var closing = false
        if j < n, c[j] == "/" { closing = true; j += 1 }
        let nameStart = j
        guard j < n, c[j].isASCII, c[j].isLetter else { return nil }
        while j < n, c[j].isASCII, c[j].isLetter || c[j].isNumber || c[j] == "-" { j += 1 }
        let name = String(c[nameStart..<j]).lowercased()
        var attrs: [(String, String)] = []
        var selfClosing = false
        while true {
            while j < n, c[j].isWhitespace || c[j] == "/" {
                selfClosing = c[j] == "/"
                j += 1
            }
            guard j < n else { return nil }
            if c[j] == ">" { break }
            selfClosing = false
            let an = j
            while j < n, !c[j].isWhitespace, c[j] != "=", c[j] != ">", c[j] != "/", c[j] != "\"", c[j] != "'" { j += 1 }
            if j == an { return nil } // stray quote
            let attrName = String(c[an..<j]).lowercased()
            var k = j
            while k < n, c[k].isWhitespace { k += 1 }
            var value = ""
            if k < n, c[k] == "=" {
                k += 1
                while k < n, c[k].isWhitespace { k += 1 }
                guard k < n else { return nil }
                if c[k] == "\"" || c[k] == "'" {
                    let q = c[k]
                    let vs = k + 1
                    var e = vs
                    while e < n, c[e] != q { e += 1 }
                    guard e < n else { return nil }
                    value = String(c[vs..<e])
                    k = e + 1
                } else {
                    let vs = k
                    while k < n, !c[k].isWhitespace, c[k] != ">" { k += 1 }
                    value = String(c[vs..<k])
                }
                j = k
            }
            attrs.append((attrName, decodeEntities(value)))
        }
        return (Tag(name: name, closing: closing, selfClosing: selfClosing, attributes: attrs), j + 1)
    }

    static func render(_ tag: Tag, allowRemote: Bool) -> String {
        guard allowedTags.contains(tag.name) else { return "" }
        if tag.closing { return "</\(tag.name)>" }
        let urlAttrs = urlAttributes[tag.name] ?? []
        var out = "<\(tag.name)"
        var seen = Set<String>()
        for (name, value) in tag.attributes where !seen.contains(name) {
            seen.insert(name)
            if urlAttrs.contains(name) {
                let ok: Bool
                switch name {
                case "href": ok = isSafeLink(value)
                case "srcset": ok = value.split(separator: ",").allSatisfy {
                        isSafeResource(String($0.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? ""), allowRemote: allowRemote)
                    }
                case "media": ok = true
                default: ok = isSafeResource(value, allowRemote: allowRemote)
                }
                if ok { out += " \(name)=\"\(MDEscape.attr(value))\"" }
                else if tag.name == "img", name == "src" {
                    // A blocked image shows its alt text instead.
                    let alt = tag.attributes.first(where: { $0.name == "alt" })?.value ?? ""
                    return alt.isEmpty ? "" : MDEscape.html("[\(alt)]")
                }
            } else if globalAttributes.contains(name) {
                out += " \(name)=\"\(MDEscape.attr(value))\""
            }
        }
        return out + ">"
    }

    // MARK: URLs

    /// Scheme of a URL as a browser would see it: entities already decoded, ASCII whitespace and
    /// control characters ignored. nil for relative URLs.
    static func scheme(_ url: String) -> String? {
        var s = ""
        for u in url.unicodeScalars where u.value > 0x20 && u.value != 0x7F {
            s.unicodeScalars.append(u)
            if u == ":" { return String(s.dropLast()).lowercased() }
            if u == "/" || u == "?" || u == "#" { return nil }
        }
        return nil
    }

    static func isProtocolRelative(_ url: String) -> Bool {
        let t = String(url.unicodeScalars.filter { $0.value > 0x20 }.map(Character.init))
        return t.hasPrefix("//") || t.hasPrefix("\\\\") || t.hasPrefix("/\\") || t.hasPrefix("\\/")
    }

    /// Link targets: web, mail, phone, and relative (incl. #fragments).
    static func isSafeLink(_ url: String) -> Bool {
        guard let s = scheme(url) else { return true }
        return ["http", "https", "mailto", "tel"].contains(s)
    }

    /// Image sources: relative paths and inline raster images always; http(s) only when remote
    /// resources are allowed.
    static func isSafeResource(_ url: String, allowRemote: Bool) -> Bool {
        if isProtocolRelative(url) { return allowRemote }
        guard let s = scheme(url) else { return true }
        switch s {
        case "http", "https": return allowRemote
        case "data":
            let lower = url.lowercased()
            return ["data:image/png", "data:image/gif", "data:image/jpeg", "data:image/jpg", "data:image/webp"]
                .contains { lower.hasPrefix($0) }
        default: return false
        }
    }

    // MARK: Entities

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}", "colon": ":",
        "tab": "\t", "newline": "\n", "sol": "/", "period": ".", "lpar": "(", "rpar": ")", "comma": ",",
        "num": "#", "quest": "?", "equals": "=", "excl": "!", "percnt": "%", "commat": "@",
    ]

    /// Decodes numeric and common named character references (`&#104;`, `&#x68;`, `&colon;`…).
    static func decodeEntities(_ s: String) -> String {
        guard s.utf8.contains(38), s.contains("&") else { return s }
        let c = Array(s)
        var out = ""
        var i = 0
        while i < c.count {
            if c[i] == "&" {
                var j = i + 1
                while j < c.count, j - i <= 33, c[j] != ";", c[j].isASCII, c[j].isLetter || c[j].isNumber || c[j] == "#" { j += 1 }
                let body = String(c[(i + 1)..<j])
                let terminated = j < c.count && c[j] == ";"
                var decoded: String?
                if body.hasPrefix("#x") || body.hasPrefix("#X") {
                    decoded = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if body.hasPrefix("#") {
                    decoded = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    decoded = named[body.lowercased()]
                }
                if let d = decoded, !body.isEmpty {
                    out += d
                    i = terminated ? j + 1 : j
                    continue
                }
            }
            out.append(c[i])
            i += 1
        }
        return out
    }
}
