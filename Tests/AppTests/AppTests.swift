import AppKit

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ cond: Bool, _ msg: @autoclosure () -> String) throws {
    if !cond { throw TestFailure(description: msg()) }
}

func expectContains(_ html: String, _ needle: String) throws {
    try expect(html.contains(needle), "expected to find \(needle.debugDescription) in:\n\(html)")
}

public enum AppTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("AppConfig returns valid non-empty application name") {
            try expect(!AppConfig.appName.isEmpty, "App name should not be empty")
        }

        testRunner("AppConfig provides version and build number") {
            try expect(!AppConfig.version.isEmpty, "Version should not be empty")
            try expect(!AppConfig.buildNumber.isEmpty, "Build number should not be empty")
        }

        testRunner("Every format command has a unique shortcut") {
            var seen = Set<String>()
            for c in FormatCommand.allCases {
                guard let s = c.shortcut else { continue }
                let key = FormatCommand.describe(s.key, s.mods)
                try expect(!seen.contains(key), "duplicate shortcut \(key) for \(c.title)")
                seen.insert(key)
            }
        }

        testRunner("Format bar moves tools into the … menu and back when resized") {
            let bar = FormatBar()
            func overflow(at width: CGFloat) -> Int {
                bar.setFrameSize(NSSize(width: width, height: FormatBar.height))
                bar.layoutSubtreeIfNeeded()
                return bar.overflowCount
            }
            let wide = overflow(at: 1400)
            let medium = overflow(at: 719)
            let narrow = overflow(at: 420)
            let wideAgain = overflow(at: 1400)
            try expect(wide == 0, "wide bar should show every tool, \(wide) hidden")
            try expect(medium > 0 && narrow > medium, "expected more hidden tools when narrower: \(medium), \(narrow)")
            try expect(wideAgain == 0, "tools should come back when widened, \(wideAgain) hidden")
        }

        testRunner("⌘Q quits only on a second press within 1.5 s") {
            let g = QuitGuard()
            let t0 = Date()
            try expect(!g.shouldQuit(now: t0), "first press must not quit")
            try expect(g.shouldQuit(now: t0.addingTimeInterval(0.8)), "second press within window quits")
            try expect(!g.shouldQuit(now: t0.addingTimeInterval(5)), "press after a quit request starts over")
            try expect(!g.shouldQuit(now: t0.addingTimeInterval(7)), "presses 2 s apart don't quit")
        }

        testRunner("Google Docs heading shortcuts (⌥⌘1–6, ⌥⌘0)") {
            try expect(FormatCommand.heading1.shortcut.map { FormatCommand.describe($0.key, $0.mods) } == "⌥⌘1", "H1")
            try expect(FormatCommand.normalText.shortcut.map { FormatCommand.describe($0.key, $0.mods) } == "⌥⌘0", "Normal")
        }
    }
}

public enum MarkdownTests {
    static func html(_ md: String) -> String { Markdown.html(from: md) }

    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("Headings (ATX, setext) with anchors") {
            try expectContains(html("# Hello *World* #"), "<h1 id=\"hello-world\">Hello <em>World</em></h1>")
            try expectContains(html("Title\n---"), "<h2 id=\"title\">Title</h2>")
            try expectContains(html("# A\n# A"), "id=\"a-1\"")
        }

        testRunner("Emphasis, strong, strikethrough, code") {
            let h = html("**b** *i* ***bi*** ~~s~~ `c<d>` snake_case_name")
            try expectContains(h, "<strong>b</strong>")
            try expectContains(h, "<em>i</em>")
            try expectContains(h, "<em><strong>bi</strong></em>")
            try expectContains(h, "<del>s</del>")
            try expectContains(h, "<code>c&lt;d&gt;</code>")
            try expectContains(h, "snake_case_name")
        }

        testRunner("Links, images, references, autolinks") {
            try expectContains(html("[a](http://x.y \"T\")"), "<a href=\"http://x.y\" title=\"T\">a</a>")
            try expectContains(html("![alt *x*](i.png)"), "<img src=\"i.png\" alt=\"alt x\">")
            try expectContains(html("[r][id]\n\n[id]: /u"), "<a href=\"/u\">r</a>")
            try expectContains(html("see https://example.com."), "<a href=\"https://example.com\">https://example.com</a>.")
            try expectContains(html("<https://a.b/c>"), "<a href=\"https://a.b/c\">")
        }

        testRunner("Lists: tight, loose, nested, ordered start, tasks") {
            let tight = html("- a\n- b")
            try expectContains(tight, "<ul>\n<li>a</li>\n<li>b</li>\n</ul>")
            try expectContains(html("- a\n\n- b"), "<li><p>a</p></li>")
            try expectContains(html("- a\n  - b"), "<li>a\n<ul>\n<li>b</li>")
            try expectContains(html("3. x\n4. y"), "<ol start=\"3\">")
            let task = html("- [x] done\n- [ ] todo")
            try expectContains(task, "class=\"contains-task-list\"")
            try expectContains(task, "disabled checked> done")
        }

        testRunner("Blockquotes and GitHub alerts") {
            try expectContains(html("> q\nlazy"), "<blockquote>\n<p>q\nlazy</p>\n</blockquote>")
            try expectContains(html("> [!TIP]\n> x"), "markdown-alert-tip")
        }

        testRunner("Code blocks: fenced with language, indented") {
            try expectContains(html("```js\nlet a = 1 < 2\n```"), "<pre><code class=\"language-js\">let a = 1 &lt; 2\n</code></pre>")
            try expectContains(html("    code"), "<pre><code>code\n</code></pre>")
        }

        testRunner("Tables with alignment and escaped pipes") {
            let h = html("| a | b |\n|:-:|--:|\n| 1 | x\\|y |")
            try expectContains(h, "<th align=\"center\">a</th>")
            try expectContains(h, "<td align=\"right\">x|y</td>")
        }

        testRunner("Thematic break, raw HTML, hard break, footnotes") {
            try expectContains(html("---"), "<hr>")
            try expectContains(html("<div>\n*raw*\n</div>"), "<div>\n*raw*\n</div>")
            try expectContains(html("a  \nb"), "a<br>\nb")
            let fn = html("x[^1]\n\n[^1]: note")
            try expectContains(fn, "<sup><a href=\"#fn-1\"")
            try expectContains(fn, "<li id=\"fn-1\">")
        }

        testRunner("Deeply nested input renders on a dispatch queue without crashing (F1)") {
            let inputs = [String(repeating: ">", count: 100_000) + " x",
                          String(repeating: "- ", count: 50_000) + "x",
                          (0..<3000).map { _ in "> - " }.joined() + "x"]
            for input in inputs {
                let done = DispatchSemaphore(value: 0)
                var out = ""
                DispatchQueue(label: "test.render").async { out = Markdown.html(from: input); done.signal() }
                try expect(done.wait(timeout: .now() + 10) == .success, "render timed out")
                try expect(!out.isEmpty, "empty output")
            }
        }

        testRunner("Adversarial inline/list input stays fast (F5)") {
            let cases = [("[](×8000", String(repeating: "[](", count: 8000)),
                         ("- ×10000", String(repeating: "- ", count: 10_000) + "x"),
                         ("*/_ ×20000", String(repeating: " *a", count: 20_000) + String(repeating: " a_", count: 20_000)),
                         ("[[[ + links", String(repeating: "[", count: 10_000) + String(repeating: "[a](b) ", count: 10_000)),
                         ("<\" ×20000", String(repeating: "<\"", count: 20_000))]
            for (name, input) in cases {
                let t = CFAbsoluteTimeGetCurrent()
                _ = Markdown.html(from: input)
                let dt = CFAbsoluteTimeGetCurrent() - t
                // Unoptimised test build: ~0.1-0.6 s now vs. 11.6 s+ (release!) before the fix.
                try expect(dt < 2.0, "\(name) took \(String(format: "%.2f", dt))s")
            }
        }

        testRunner("HTML is escaped in text") {
            try expectContains(html("a < b & c"), "a &lt; b &amp; c")
        }

        testRunner("Standalone HTML document embeds GitHub CSS") {
            let doc = HTMLTemplate.standalone(body: "<p>x</p>", title: "T", theme: .auto)
            try expectContains(doc, "prefers-color-scheme: dark")
            try expectContains(doc, "<article class=\"markdown-body\">")
        }
    }
}

public enum FormatterTests {
    static func run(_ op: FormatOp, _ text: String, _ sel: NSRange) -> (String, NSRange) {
        guard let e = MarkdownFormatter.edit(for: op, in: text as NSString, selection: sel) else { return (text, sel) }
        let out = (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
        return (out, e.selection)
    }

    static let bold = FormatOp.wrap(prefix: "**", suffix: "**", placeholder: "bold text")
    static let italic = FormatOp.wrap(prefix: "*", suffix: "*", placeholder: "italic text")

    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("Bold wraps selection and toggles off") {
            let (a, s) = run(bold, "hello world", NSRange(location: 6, length: 5))
            try expect(a == "hello **world**", a)
            let (b, _) = run(bold, a, s)
            try expect(b == "hello world", b)
        }

        testRunner("Bold with caret wraps the word; empty inserts placeholder") {
            let (a, _) = run(bold, "hello world", NSRange(location: 8, length: 0))
            try expect(a == "hello **world**", a)
            let (b, s) = run(bold, "x ", NSRange(location: 2, length: 0))
            try expect(b == "x **bold text**" && s == NSRange(location: 4, length: 9), b)
        }

        testRunner("Italic does not unwrap bold") {
            let (a, _) = run(italic, "**word**", NSRange(location: 2, length: 4))
            try expect(a == "***word***", a)
        }

        testRunner("Headings set level and reset to normal text") {
            let (a, _) = run(.heading(2), "# Title", NSRange(location: 3, length: 0))
            try expect(a == "## Title", a)
            let (b, _) = run(.heading(0), a, NSRange(location: 3, length: 0))
            try expect(b == "Title", b)
            let (c, _) = run(.heading(1), "- item", NSRange(location: 0, length: 0))
            try expect(c == "# item", c)
        }

        testRunner("Lists toggle and convert") {
            let (a, _) = run(.bulletList, "a\nb", NSRange(location: 0, length: 3))
            try expect(a == "- a\n- b", a)
            let (b, _) = run(.bulletList, a, NSRange(location: 0, length: 7))
            try expect(b == "a\nb", b)
            let (c, _) = run(.numberedList, a, NSRange(location: 0, length: 7))
            try expect(c == "1. a\n2. b", c)
            let (d, _) = run(.taskList, "x", NSRange(location: 0, length: 0))
            try expect(d == "- [ ] x", d)
        }

        testRunner("Blockquote and indent toggle") {
            let (a, _) = run(.blockquote, "q", NSRange(location: 0, length: 0))
            try expect(a == "> q", a)
            let (b, _) = run(.blockquote, a, NSRange(location: 2, length: 0))
            try expect(b == "q", b)
            let (c, _) = run(.indent, "- a", NSRange(location: 0, length: 0))
            try expect(c == "    - a", c)
            let (d, _) = run(.outdent, c, NSRange(location: 0, length: 0))
            try expect(d == "- a", d)
        }

        testRunner("Link wraps selection and selects url placeholder") {
            let (a, s) = run(.link, "go here", NSRange(location: 3, length: 4))
            try expect(a == "go [here](url)" && s == NSRange(location: 10, length: 3), "\(a) \(s)")
        }

        testRunner("Code block wraps lines; clear formatting strips inline markup") {
            let (a, _) = run(.codeBlock, "x = 1", NSRange(location: 0, length: 5))
            try expect(a == "```\nx = 1\n```", a)
            let (b, _) = run(.clearFormatting, "**a** *b* `c` ~~d~~ <ins>e</ins>", NSRange(location: 0, length: 0))
            try expect(b == "a b c d e", b)
        }

        testRunner("Return continues and ends lists") {
            let t = "- a" as NSString
            let e = MarkdownFormatter.continueList(text: t, selection: NSRange(location: 3, length: 0))
            try expect(e?.replacement == "\n- ", "\(String(describing: e))")
            let n = MarkdownFormatter.continueList(text: "3. x" as NSString, selection: NSRange(location: 4, length: 0))
            try expect(n?.replacement == "\n4. ", "\(String(describing: n))")
            let end = MarkdownFormatter.continueList(text: "- a\n- " as NSString, selection: NSRange(location: 6, length: 0))
            try expect(end?.replacement == "", "\(String(describing: end))")
            let task = MarkdownFormatter.continueList(text: "- [x] a" as NSString, selection: NSRange(location: 7, length: 0))
            try expect(task?.replacement == "\n- [ ] ", "\(String(describing: task))")
        }
    }
}


public enum HardeningTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("Link policy: web opens, local executables are revealed, odd schemes confirm (F2)") {
            let base = URL(fileURLWithPath: "/tmp/repo/")
            try expect(LinkPolicy.action(for: URL(string: "https://example.com")!) == .openExternally(URL(string: "https://example.com")!), "https")
            let cmd = URL(fileURLWithPath: "tools/setup.command", relativeTo: base)
            try expect(LinkPolicy.action(for: cmd) == .revealInFinder(cmd), ".command must not launch")
            let app = URL(fileURLWithPath: "/tmp/repo/Evil.app")
            try expect(LinkPolicy.action(for: app) == .revealInFinder(app), ".app must not launch")
            let md = URL(fileURLWithPath: "/tmp/repo/docs/guide.md")
            try expect(LinkPolicy.action(for: md) == .openDocument(md), "markdown opens in editor")
            let vs = URL(string: "vscode://file/etc/passwd")!
            try expect(LinkPolicy.action(for: vs) == .confirm(vs), "custom scheme needs confirmation")
        }

        testRunner("Decoding: legacy 8-bit files are not read as UTF-16; encoding round-trips (F3)") {
            let cp1252 = "# Café résumé\n".data(using: .windowsCP1252)!
            let d = TextDecoding.decode(cp1252)
            try expect(d.text == "# Café résumé\n", "got \(d.text.debugDescription)")
            try expect(d.encoding == .windowsCP1252, "encoding \(d.encoding)")
            try expect(TextDecoding.encode(d.text, encoding: d.encoding, hasBOM: d.hasBOM).data == cp1252, "round-trip")
            let bomUTF8 = Data([0xEF, 0xBB, 0xBF]) + Data("x".utf8)
            let b = TextDecoding.decode(bomUTF8)
            try expect(b.text == "x" && b.hasBOM, "utf8 bom")
            try expect(TextDecoding.encode(b.text, encoding: b.encoding, hasBOM: b.hasBOM).data == bomUTF8, "bom kept")
            let utf16 = Data([0xFF, 0xFE]) + "hé".data(using: .utf16LittleEndian)!
            try expect(TextDecoding.decode(utf16).text == "hé", "utf16 with bom")
            let emoji = TextDecoding.encode("é 🙂", encoding: .windowsCP1252, hasBOM: false)
            try expect(emoji.encoding == .utf8 && String(data: emoji.data, encoding: .utf8) == "é 🙂", "unrepresentable falls back to utf8")
        }

        testRunner("Incremental highlighting matches a full highlight (F4)") {
            let doc = "# Title\n\nSome **bold** text\n\n```swift\nlet a = 1\n```\n\n<!-- note\nspans -->\n\n- item\n\nSetext\n"
            let h = MarkdownHighlighter()
            let ts = NSTextStorage(string: doc)
            h.highlight(ts)
            let edits: [(NSRange, String)] = [
                (NSRange(location: 22, length: 0), " *it*"),        // inline
                (NSRange(location: 0, length: 0), "x"),             // first line
                (NSRange(location: 38, length: 0), "b"),            // inside code block
                (NSRange(location: (doc as NSString).length, length: 0), "---"), // setext underline below
            ]
            for (r, str) in edits {
                let loc = min(r.location, ts.length)
                ts.replaceCharacters(in: NSRange(location: loc, length: 0), with: str)
                h.highlight(ts, edited: NSRange(location: loc, length: (str as NSString).length))
                let fresh = NSTextStorage(string: ts.string)
                MarkdownHighlighter().highlight(fresh)
                try expect(ts.isEqual(to: fresh), "attributes differ after inserting \(str.debugDescription) at \(loc)")
            }
        }

        testRunner("Highlighting one edit in a 312 KB document is fast (F4)") {
            let doc = String(repeating: "## Title\n\nSome **bold** and *it* `code` [l](http://x.y) text.\n\n- item\n- item\n\n", count: 4000)
            let ts = NSTextStorage(string: doc)
            let h = MarkdownHighlighter()
            h.highlight(ts)
            let loc = ts.length / 2
            ts.replaceCharacters(in: NSRange(location: loc, length: 0), with: "x")
            let t = CFAbsoluteTimeGetCurrent()
            h.highlight(ts, edited: NSRange(location: loc, length: 1))
            let dt = CFAbsoluteTimeGetCurrent() - t
            try expect(dt < 0.05, "edit took \(String(format: "%.3f", dt))s")
            let c = NSTextStorage(string: String(repeating: "<!-- x\n", count: 8000))
            let t2 = CFAbsoluteTimeGetCurrent()
            MarkdownHighlighter().highlight(c)
            let dt2 = CFAbsoluteTimeGetCurrent() - t2
            try expect(dt2 < 1, "unclosed comments took \(String(format: "%.2f", dt2))s")
        }

        testRunner("Remote subresources are stripped before rich-text conversion (F7)") {
            let md = #"<p><img src="https://t.example/p.png" alt="logo"><img src="local.png" alt="ok"></p><iframe src="//x.example"></iframe><a href="https://keep.example">k</a><div style="background:url(http://x/y.png)"></div>"#
            let out = Exporter.richHTML(markdown: md, title: "t")
            try expect(!out.contains("t.example") && !out.contains("x.example") && !out.contains("http://x/"), out)
            try expect(out.contains("[logo]") && out.contains("local.png") && out.contains("https://keep.example"), out)
        }

        testRunner("Raw HTML is sanitized; formatting tags survive (ALERT-006)") {
            let md = """
            <details open><summary>More</summary><kbd>⌘</kbd> x<sup>2</sup><br><img src="a.png" width="40" alt="a"></details>

            <p align="center" onclick="x()" style="color:red" class="c">centered</p>

            <script>alert(1)</script>

            <iframe src="https://e.example"></iframe><svg onload="x()"><circle/></svg><style>p{}</style>

            <base href="https://e.example/"><meta http-equiv="refresh" content="0;url=https://e.example"><link rel="stylesheet" href="s.css">

            <img src=x onerror=alert(1)> <a href="jav&#x61;script:alert(1)">a</a> <a href="java&#9;script:x">b</a> <form action="/x"><input></form>
            """
            let out = Markdown.html(from: md)
            for bad in ["<script", "alert(1)</", "onerror", "onclick", "onload", "style=", "class=\"c\"", "<iframe", "<svg",
                        "<style", "<base", "<meta", "<link", "javascript", "java\t", "<form", "<input"] {
                try expect(!out.lowercased().contains(bad.lowercased()), "\(bad) survived: \(out)")
            }
            for good in ["<details open=\"\">", "<summary>", "<kbd>", "<sup>2</sup>", "<br>", "width=\"40\"", "<p align=\"center\">"] {
                try expect(out.contains(good), "\(good) missing: \(out)")
            }
        }

        testRunner("Markdown links and images never carry script URLs (ALERT-006)") {
            for md in ["[x](javascript:alert(1))", "[x](JaVaScRiPt:alert(1))", "[r]\n\n[r]: javascript:alert(1)",
                       "![i](javascript:alert(1))", "<javascript:alert(1)>", "[x](data:text/html,<b>)", "[x](&#106;avascript:alert(1))"] {
                let out = Markdown.html(from: md).lowercased()
                try expect(!out.contains("href=\"javascript") && !out.contains("src=\"javascript") && !out.contains("href=\"data:"), "\(md) → \(out)")
            }
            try expect(Markdown.html(from: "[ok](https://a.example) [rel](docs/x.md) [m](mailto:a@b.c)").components(separatedBy: "href=").count == 4, "safe links kept")
        }

        testRunner("No remote resource survives remote-free rendering (ALERT-001/008)") {
            let h = "https://t.example"
            let corpus = [
                "<base href=\"\(h)/\"><img src=\"x.png\">", "<img src=\"&#104;ttps://t.example/a\">", "<img src=\"ht&#9;tps://t.example/b\">",
                "<img src=\"a.png\" srcset=\"a.png 1x, \(h)/c 2x\">", "<svg><image href=\"\(h)/d\"/></svg>", "<p style=\"background:u\\72l(\(h)/e)\">x</p>",
                "<style>@\\69mport url(\(h)/f);</style>", "<table/background=\"\(h)/g\"><tr><td>x</td></tr></table>",
                "<meta http-equiv=\"refresh\" content=\"0;url=\(h)/h\">", "<link rel=\"stylesheet\" href=\"\(h)/i.css\">", "<svg><use href=\"\(h)/j#x\"/></svg>",
                "<p style=\"background-image:image-set('\(h)/k' 1x)\">i</p>", "<input type=\"image\" src=\"&#x68;ttps://t.example/l\">",
                "<table background=\"&#104;ttps://t.example/m\"><tr><td>q</td></tr></table>", "<picture><source srcset=\"\(h)/n\"><img src=\"a.png\"></picture>",
                "![x](\(h)/o.png)", "<img src=\"//t.example/p\">", "<object data=\"\(h)/q\"></object>", "<iframe src=\"\(h)/r\"></iframe>",
            ]
            for md in corpus {
                let out = Exporter.richHTML(markdown: md, title: "t")
                try expect(!out.contains("t.example"), "\(md) → \(out)")
            }
            try expect(Exporter.richHTML(markdown: "![logo](\(h)/x.png) [k](\(h))", title: "t").contains("[logo]"), "alt text replaces blocked image")
        }

        testRunner("Quick Look HTML forbids script and remote loads (ALERT-002)") {
            let html = HTMLTemplate.standalone(body: "", title: "t", theme: .auto, remoteImages: false)
            try expect(html.contains("Content-Security-Policy") && html.contains("script-src 'none'"), "CSP missing")
            try expect(!HTMLTemplate.csp(remoteImages: false).contains("http"), "remote images allowed in Quick Look")
            try expect(HTMLTemplate.csp(remoteImages: true).contains("https:"), "exports should keep remote images")
        }

        testRunner("Decoding never changes bytes the user did not edit (ALERT-004)") {
            func b(_ s: String) -> [UInt8] { Array(s.utf8) }
            var cases: [[UInt8]] = []
            cases.append(b("Copyright ") + [0xA9] + b(" 2020\n"))            // Latin-1 ©
            cases.append([0xFE, 0xFF, 0x00, 0x41, 0x00])                       // UTF-16BE, odd length
            cases.append([0xFF, 0xFE, 0x41, 0x00, 0x3D, 0xD8, 0x42, 0x00])     // UTF-16LE, unpaired surrogate
            cases.append([0xFF, 0xFE, 0x41, 0x42, 0x43])                       // Latin-1 starting with ÿþ
            cases.append(b("caf") + [0xE9] + b("\n"))
            cases.append([0xEF, 0xBB, 0xBF] + b("(c) ") + [0xA9])
            for bytes in cases {
                let d = TextDecoding.decode(Data(bytes))
                try expect(!d.text.contains("\u{FFFD}"), "U+FFFD for \(bytes)")
                if d.repairedBytes == 0 {
                    try expect(TextDecoding.encode(d.text, encoding: d.encoding, hasBOM: d.hasBOM).data == Data(bytes), "round-trip \(bytes)")
                }
            }
            let c = TextDecoding.decode(Data(b("Copyright ") + [0xA9] + b(" 2020")))
            try expect(c.text == "Copyright © 2020", c.text)
            // Mostly UTF-8 with one stray Latin-1 byte: UTF-8 text stays intact, only the stray byte is repaired.
            var mixed = b("Zażółć gęślą — café ")
            mixed.append(0xE9)
            let m = TextDecoding.decode(Data(mixed))
            try expect(m.encoding == .utf8 && m.repairedBytes == 1 && m.text == "Zażółć gęślą — café é", m.text)
            let saved = TextDecoding.encode(m.text + "→", encoding: m.encoding, hasBOM: m.hasBOM)
            try expect(String(data: saved.data, encoding: .utf8) == "Zażółć gęślą — café é→", "no double encoding")
        }

        // Growth check that works in unoptimised test builds: quadratic work grows ~4× per doubling.
        // A busy machine can stretch one timing several-fold, so a failure must repeat: quadratic
        // growth fails every attempt, scheduling noise doesn't (a flaky failure blocked releases).
        func expectLinear(_ name: String, _ make: (Int) -> String, _ n: Int, _ run: (String) -> Void) throws {
            func time(_ k: Int) -> Double { // best of three, to filter scheduling noise
                let s = make(k)
                return (0..<3).map { _ in let a = CFAbsoluteTimeGetCurrent(); run(s); return CFAbsoluteTimeGetCurrent() - a }.min()!
            }
            _ = time(n / 8) // warm up
            var report: [String] = []
            for _ in 0..<3 {
                let t1 = time(n / 2), t2 = time(n)
                if t2 < 0.25 || t2 / max(t1, 1e-3) < 3.3 { return }
                report.append(String(format: "%.2f→%.2fs", t1, t2))
            }
            try expect(false, "\(name): \(report.joined(separator: ", ")) per doubling (3 attempts)")
        }

        testRunner("Renderer stays linear on adversarial input (ALERT-003/009)") {
            let gens: [(String, (Int) -> String)] = [
                ("emphasis", { String(repeating: "*a* ", count: $0 / 4) }),
                ("strike", { String(repeating: "~~a", count: $0 / 3) }),
                ("comments", { "x " + String(repeating: "a <!-- ", count: $0 / 7) }),
                ("footnotes", { n in (0..<(n / 20)).map { "[^f\($0)] " }.joined() + "\n\n" + (0..<(n / 40)).map { "[^f\($0)]: x\n" }.joined() }),
                ("backticks", { n in var k = 1, o = "x "; while o.utf8.count < n { o += String(repeating: "`", count: k) + " a "; k += 1 }; return o }),
                ("autolink-parens", { "http://a.example/" + String(repeating: ")", count: $0) }),
            ]
            for (name, make) in gens { try expectLinear(name, make, 200_000) { _ = Markdown.html(from: $0) } }
            try expect(Markdown.html(from: "*a* **b** ~~c~~ _d_").contains("<em>a</em> <strong>b</strong> <del>c</del> <em>d</em>"), "emphasis still correct")
        }

        testRunner("Highlighting and stats scale to large documents (ALERT-005)") {
            let para = "Some **bold** text with `code` and a [link](http://x) here.\n- item one\n> quote\n\n"
            try expectLinear("highlight", { String(repeating: para, count: $0 / para.utf8.count) }, 600_000) {
                MarkdownHighlighter().highlight(NSTextStorage(string: $0))
            }
            try expectLinear("stats", { String(repeating: "word ", count: $0 / 5) }, 400_000) { str in
                let ns = str as NSString
                _ = EditorViewController.textStats(ns, selection: NSRange(location: ns.length, length: 0))
            }
            let big = String(repeating: "word ", count: 20_000) as NSString
            try expect(EditorViewController.textStats(big, selection: NSRange(location: 0, length: 0)).words == 20_000, "word count")
            let small = EditorViewController.textStats("ab cd\nef 😀" as NSString, selection: NSRange(location: 8, length: 0))
            try expect(small.words == 4 && small.characters == 10 && small.line == 2 && small.column == 3, "\(small)")
        }

        testRunner("Highlighter patterns stay linear on one long line (ALERT-010)") {
            for (name, unit) in [("bold", "**a "), ("italic", " *a"), ("underscore", " _a"), ("strike", "~~a "), ("link", "["),
                                 ("reflink", "[a"), ("angle", "<http:a"), ("footnote", "[^"), ("bold-stars", "**a*")] {
                try expectLinear(name, { "# T\n\n" + String(repeating: unit, count: $0 / unit.count) + "\n" }, 40_000) {
                    MarkdownHighlighter().highlight(NSTextStorage(string: $0))
                }
            }
            // Formatting is still recognised.
            let ts = NSTextStorage(string: "a **b *c* d** e *f* ~~g~~ [h](u) [^n] <https://x.y>")
            MarkdownHighlighter().highlight(ts)
            func font(_ i: Int) -> NSFont { ts.attribute(.font, at: i, effectiveRange: nil) as! NSFont }
            func has(_ k: NSAttributedString.Key, _ i: Int) -> Bool { ts.attribute(k, at: i, effectiveRange: nil) != nil }
            let str = ts.string as NSString
            try expect(font(str.range(of: "b").location).fontDescriptor.symbolicTraits.contains(.bold), "bold with italic inside")
            try expect(font(str.range(of: "f").location).fontDescriptor.symbolicTraits.contains(.italic), "italic")
            try expect(has(.strikethroughStyle, str.range(of: "g").location), "strike")
            try expect(has(.underlineStyle, str.range(of: "x.y").location), "angle link")
            let plain = ts.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor
            try expect(ts.attribute(.foregroundColor, at: str.range(of: "h").location, effectiveRange: nil) as! NSColor != plain, "link text coloured")
            try expect(ts.attribute(.foregroundColor, at: str.range(of: "^n").location, effectiveRange: nil) as! NSColor != plain, "footnote coloured")
            // Clear formatting still strips markers.
            let text = "**bold** __b2__ *it* _u_ ~~st~~ `c`" as NSString
            let edit = MarkdownFormatter.clearFormatting(text, NSRange(location: 0, length: text.length))
            try expect(edit?.replacement == "bold b2 it u st c", edit?.replacement ?? "nil")
        }

        testRunner("Print/PDF web view runs no page scripts (F8)") {
            try expect(!WebPrintJob.makeConfiguration().defaultWebpagePreferences.allowsContentJavaScript, "JS enabled")
        }
    }
}


public enum WindowingTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("Tabs live in one window: add, select, ⌘9, close, move, merge") {
            let host = DocumentWindowController()
            let tabs = (0..<3).map { _ in EditorWindowController() }
            tabs.forEach { host.add($0) }
            try expect(host.tabs.count == 3 && host.activeTab === tabs[2], "3 tabs, last active")
            try expect(host.tabs.allSatisfy { $0.window === host.window }, "tabs share the host window")
            try expect(DocumentWindowController.all.filter { $0 === host }.count == 1, "host registered once")
            host.selectTab(number: 1)
            try expect(host.activeTab === tabs[0], "⌘1 selects first")
            host.selectTab(number: 9)
            try expect(host.activeTab === tabs[2], "⌘9 selects last")
            host.showNextDocumentTab(nil)
            try expect(host.activeTab === tabs[0], "next wraps around")
            host.remove(tabs[0])
            try expect(host.tabs.count == 2 && host.activeTab === tabs[1], "closing active selects neighbour")
            host.moveTabToNewWindow(nil)
            try expect(host.tabs.count == 1 && tabs[1].host !== host, "tab moved to its own window")
            let other = tabs[1].host!
            host.mergeAllWindows(nil)
            try expect(host.tabs.count == 2 && other.tabs.isEmpty, "merge brings tabs back")
            host.remove(tabs[1])
            host.remove(tabs[2])
            try expect(host.tabs.isEmpty && !DocumentWindowController.all.contains { $0 === host }, "empty window closes")
        }

        testRunner("Editor / preview panes toggle and never both hide") {
            UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames EditorPreviewSplit")
            let host = DocumentWindowController()
            let tab = EditorWindowController()
            host.add(tab)
            host.window?.setContentSize(NSSize(width: 1200, height: 700))
            host.window?.contentView?.layoutSubtreeIfNeeded()
            let ed = tab.editor
            ed.view.layoutSubtreeIfNeeded()
            try expect(ed.isPaneVisible(.editor) && ed.isPaneVisible(.preview), "both visible initially: \(ed.debugPaneFrames)")
            ed.togglePane(.preview)
            try expect(ed.isPaneVisible(.editor) && !ed.isPaneVisible(.preview), "preview hidden")
            ed.togglePane(.editor)
            try expect(ed.isPaneVisible(.preview) && !ed.isPaneVisible(.editor), "hiding last pane swaps to the other")
            ed.togglePane(.editor)
            try expect(ed.isPaneVisible(.editor) && ed.isPaneVisible(.preview), "both back")
            host.remove(tab)
        }

        testRunner("Save on focus loss writes edited documents only when enabled") {
            let fa = FocusAutosave.shared
            fa.start() // normally done by AppDelegate at launch
            let wasEnabled = fa.isEnabled
            defer { fa.isEnabled = wasEnabled }
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("focus-\(UUID().uuidString).md")
            try "# Original\n".write(to: tmp, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let doc = try MarkdownDocument(contentsOf: tmp, ofType: "net.daringfireball.markdown")
            NSDocumentController.shared.addDocument(doc)
            doc.makeWindowControllers()
            defer { doc.close() }
            let tv = (doc.windowControllers.first as! EditorWindowController).editor.textView!
            tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0))
            tv.insertText("edited", replacementRange: tv.selectedRange())
            doc.updateChangeCount(.changeDone)
            func waitForFile(_ predicate: (String) -> Bool) -> String {
                let deadline = Date().addingTimeInterval(3)
                var text = ""
                repeat {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                    text = (try? String(contentsOf: tmp, encoding: .utf8)) ?? ""
                } while !predicate(text) && Date() < deadline
                return text
            }
            fa.isEnabled = false
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            try expect(!waitForFile { $0.contains("edited") }.contains("edited"), "must not save when disabled")
            fa.isEnabled = true
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            let text = waitForFile { $0.contains("edited") }
            try expect(text.contains("edited"), "file not saved on focus loss: \(text.debugDescription)")
            try expect(FocusAutosave.documentsToSave([doc]).isEmpty, "document should be clean after saving")
        }

        testRunner("A preview dragged shut (and remembered) can be reopened with the toggle") {
            // Simulate the saved state of a preview collapsed by dragging the divider fully right.
            UserDefaults.standard.set(["0.000000, 0.000000, 1199.000000, 642.000000, NO, NO",
                                       "1200.000000, 0.000000, 0.000000, 642.000000, NO, NO"],
                                      forKey: "NSSplitView Subview Frames EditorPreviewSplit")
            let host = DocumentWindowController()
            let tab = EditorWindowController()
            host.add(tab)
            host.window?.setContentSize(NSSize(width: 1200, height: 700))
            host.window?.contentView?.layoutSubtreeIfNeeded()
            let ed = tab.editor
            ed.view.layoutSubtreeIfNeeded()
            try expect(!ed.isPaneVisible(.preview), "preview starts collapsed: \(ed.debugPaneFrames)")
            ed.togglePane(.preview)
            try expect(ed.isPaneVisible(.preview) && ed.isPaneVisible(.editor), "toggle reopens it: \(ed.debugPaneFrames)")
            host.remove(tab)
            UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames EditorPreviewSplit")
        }
    }
}

public enum PerformanceTests {
    /// The pre-PERF-008 implementation, kept as the reference for the equivalence fuzz test.
    static func referenceScanStructure(_ s: NSString) -> MarkdownHighlighter.Structure {
        var st = MarkdownHighlighter.Structure()
        let len = s.length
        // Fenced code: walk lines, check the first non-space characters.
        var lineStart = 0
        var fenceChar: unichar = 0
        var fenceStart = 0
        while lineStart < len {
            var start = 0, end = 0, contentsEnd = 0
            s.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
            var i = start
            while i < contentsEnd, s.character(at: i) == 32 { i += 1 }
            if i - start < 4, i + 2 < contentsEnd {
                let c = s.character(at: i)
                if (c == 96 || c == 126), s.character(at: i + 1) == c, s.character(at: i + 2) == c {
                    if fenceChar == 0 {
                        fenceChar = c
                        fenceStart = start
                        st.signature.append(c)
                    } else if c == fenceChar {
                        var j = i
                        while j < contentsEnd, s.character(at: j) == c { j += 1 }
                        while j < contentsEnd, s.character(at: j) == 32 || s.character(at: j) == 9 { j += 1 }
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

        // HTML comments: one forward pass.
        var pos = 0
        while pos < len {
            let open = s.range(of: "<!--", options: .literal, range: NSRange(location: pos, length: len - pos))
            if open.location == NSNotFound { break }
            st.signature.append(60)
            let after = NSMaxRange(open)
            let close = s.range(of: "-->", options: .literal, range: NSRange(location: after, length: len - after))
            let endPos = close.location == NSNotFound ? len : NSMaxRange(close)
            if close.location != NSNotFound { st.signature.append(62) }
            st.comments.append(NSRange(location: open.location, length: endPos - open.location))
            pos = endPos
        }
        return st
    }

    /// Spins the run loop until `done()` or the timeout; returns whether `done()` became true.
    @discardableResult
    static func wait(_ timeout: TimeInterval = 10, _ done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return done()
    }

    static func makeEditor() -> (DocumentWindowController, EditorWindowController) {
        UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames EditorPreviewSplit")
        let host = DocumentWindowController()
        let tab = EditorWindowController()
        host.add(tab)
        host.window?.setContentSize(NSSize(width: 1200, height: 700))
        host.window?.contentView?.layoutSubtreeIfNeeded()
        tab.editor.view.layoutSubtreeIfNeeded()
        return (host, tab)
    }

    /// Waits for the render triggered after `renders` to finish and its script to complete.
    static func settle(_ ed: EditorViewController, after renders: Int) throws {
        try expect(wait { ed.renderCount > renders && ed.isPreviewSettled }, "preview did not settle")
    }

    static func previewHTML(_ ed: EditorViewController) throws -> String {
        var html: String?
        ed.previewContentHTML { html = $0 ?? "" }
        try expect(wait { html != nil }, "no preview HTML")
        return html!
    }

    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("Fragments join to the full HTML; raw HTML balance decides splice safety (PERF-002)") {
            let doc = "# A\n\npara [^n]\n\n<details><summary>S</summary>\n\nhidden\n\n</details>\n\n[^n]: note"
            let f = Markdown.fragments(from: doc)
            try expect(f.html.joined() == Markdown.html(from: doc), "joined fragments differ")
            try expect(!f.selfContained, "unbalanced <details> must disable splicing")
            try expect(f.html.last?.hasPrefix("<section class=\"footnotes\"") == true, "footnotes are the last fragment")
            try expect(Markdown.fragments(from: "a <b>c</b>\n\n<div>\nx\n</div>\n\n<br> <img src=x.png>").selfContained, "balanced raw HTML")
            try expect(!Markdown.fragments(from: "a <b>c\n\nd").selfContained, "unclosed inline tag")
            try expect(!Markdown.tagsBalanced("<p><b></p></b>") && Markdown.tagsBalanced("<p>a<br><img src=\"x\"></p>"), "tagsBalanced")
        }

        testRunner("Preview update diff touches only the changed fragments (PERF-002)") {
            let u = PreviewUpdate(old: ["a", "b", "c", "d"], new: ["a", "B", "c", "d"], selfContained: true, base: 1, version: 2)
            try expect(u.isSplice && u.fragments! == ["a", "B", "c", "d"], "splice")
            try expect(u.script!.contains("m.length!==4") && u.script!.contains("var x=1<m.length") && u.script!.contains("var end=2<m.length"), u.script!)
            try expect(!u.script!.contains("\"a\"") && !u.script!.contains("<!--b-->c"), "unchanged fragments are not resent")
            try expect(PreviewUpdate(old: ["a"], new: ["a"], selfContained: true, base: 1, version: 2).script == nil, "no-op")
            let full = PreviewUpdate(old: ["a"], new: ["x"], selfContained: false, base: 1, version: 2)
            try expect(!full.isSplice && full.fragments == nil && full.script!.contains("innerHTML="), "unbalanced → full")
        }

        testRunner("Spliced preview DOM equals a full replacement across random edits (PERF-002)") {
            let (host, tab) = makeEditor()
            defer { host.remove(tab) }
            let ed = tab.editor
            try expect(ed.isPaneVisible(.preview), "preview visible")
            ed.markdown = "# Title\n\nIntro with [ref] and footnote[^a].\n\n## Title\n\n- one\n- two\n\n[ref]: https://example.com\n[^a]: Note."
            try settle(ed, after: 0)
            let snippets = ["\n\n# Title\n", "\n\n- item\n", "*em* ", "\n\n[ref]: https://other.example\n", "[^a] ", "\n\n[^b]: B\n",
                            "\n\n```\ncode\n", "\n```\n", "<b>bold</b> ", "\n\n<div>\nblock\n</div>\n", "\n\n<details>\n\n", "</details>",
                            "| a | b |\n|---|---|\n| 1 | 2 |\n", "\n\n> quote\n", "x", "\n\n---\n", "<!-- c -->", "\n\n"]
            var rng: UInt64 = 0x2545F4914F6CDD1D
            func rand(_ n: Int) -> Int { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return Int(rng % UInt64(n)) }
            let tv = ed.textView!
            for step in 0..<40 {
                let len = tv.string.utf16.count
                let renders = ed.renderCount
                if rand(4) == 0, len > 10 {
                    let at = rand(len - 5)
                    tv.insertText("", replacementRange: NSRange(location: at, length: 1 + rand(5)))
                } else {
                    tv.insertText(snippets[rand(snippets.count)], replacementRange: NSRange(location: rand(len + 1), length: 0))
                }
                try settle(ed, after: renders)
                let spliced = try previewHTML(ed)
                let before = ed.renderCount
                ed.forceFullPreviewUpdate()
                try settle(ed, after: before)
                let full = try previewHTML(ed)
                try expect(spliced == full, "step \(step): spliced DOM differs from full replace\n--- text:\n\(tv.string)")
            }
        }

        testRunner("Scroll sync keeps one script in flight and lands on the final position (PERF-004)") {
            let (host, tab) = makeEditor()
            defer { host.remove(tab) }
            let ed = tab.editor
            ed.markdown = (0..<3000).map { "Line \($0) with some words.\n" }.joined()
            try settle(ed, after: 0)
            wait(0.3) { false }
            let clip = ed.textView.enclosingScrollView!.contentView
            let maxY = ed.textView.frame.height - clip.bounds.height
            try expect(maxY > 1000, "document is scrollable: \(maxY)")
            let sent = ed.scrollSyncScriptsSent
            for k in 1...200 { clip.scroll(to: NSPoint(x: 0, y: maxY * CGFloat(k) / 400)) } // 200 events, no run-loop turns
            try expect(ed.scrollSyncScriptsSent - sent <= 1, "scripts sent during burst: \(ed.scrollSyncScriptsSent - sent)")
            var ratio: Double?
            try expect(wait {
                ed.webView.evaluateJavaScript("window.scrollY/(document.documentElement.scrollHeight-window.innerHeight)") { r, _ in ratio = r as? Double }
                return ratio.map { abs($0 - 0.5) < 0.01 } ?? false
            }, "preview ends at the editor's final position (ratio \(ratio ?? -1))")
            try expect(ed.scrollSyncScriptsSent - sent <= 3, "total scripts: \(ed.scrollSyncScriptsSent - sent)")
        }

        testRunner("Buffered structure scan matches the reference implementation (PERF-008)") {
            let pieces = ["```", "~~~", "````", "   ```", "    ```", "``", "` ``", "<!--", "-->", "<!-", "--", ">", "x", "é", "😀",
                          "\n", "\r", "\r\n", "\u{85}", "\u{2028}", "\u{2029}", " ", "\t", "swift", "~~~ ", "``` \t"]
            var rng: UInt64 = 0x9E3779B97F4A7C15
            func rand(_ n: Int) -> Int { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return Int(rng % UInt64(n)) }
            for k in 0..<3000 {
                let text = (0..<rand(60)).map { _ in pieces[rand(pieces.count)] }.joined() as NSString
                let a = MarkdownHighlighter.scanStructure(text), b = PerformanceTests.referenceScanStructure(text)
                try expect(a == b, "case \(k): \((text as String).debugDescription)\nnew \(a)\nref \(b)")
            }
        }

        testRunner("Progressive highlighting on open ends identical to a full pass, edits included (PERF-010)") {
            let (host, tab) = makeEditor()
            defer { host.remove(tab) }
            let ed = tab.editor
            let section = "# Heading\n\nSome **bold**, *em*, `code`, [link](u) and <b>tag</b>.\n\n- item\n> quote\n\n```\ncode block\n```\n\n"
            // No fences/comments: edits keep the block structure, so only the progressive pass's own
            // bookkeeping (noteEdit) keeps the highlighting complete.
            let plain = "# Heading\n\nSome **bold**, *em*, `code`, [link](u) and <b>tag</b>.\n\n- item\n> quote\n\n"
            ed.markdown = String(repeating: plain, count: 5000) // ~370 KB
            try expect(ed.highlighter.progressFrom != nil, "large document is highlighted progressively")
            let tv = ed.textView!
            tv.insertText("start **x** ", replacementRange: NSRange(location: 0, length: 0))       // before the pass position
            let mid = tv.string.utf16.count / 2
            tv.insertText("mid *y* ", replacementRange: NSRange(location: mid, length: 0))          // in the pending region
            tv.insertText("", replacementRange: NSRange(location: 200, length: 30))                 // deletion before the pass
            tv.insertText("", replacementRange: NSRange(location: 1000, length: 5000))              // large deletion before the pass
            try expect(wait { ed.highlighter.progressFrom == nil }, "progressive pass finishes")
            let reference = NSTextStorage(string: tv.string)
            MarkdownHighlighter().highlight(reference)
            try expect(tv.textStorage!.isEqual(to: reference), "attributes differ from a full highlight")
            // Small documents are still highlighted synchronously.
            ed.markdown = section
            try expect(ed.highlighter.progressFrom == nil, "small document highlighted at once")
        }

        testRunner("Line numbers: setting toggles the gutter; incremental index matches a rebuild") {
            let was = LineNumberSettings.isEnabled
            defer { LineNumberSettings.isEnabled = was }
            LineNumberSettings.isEnabled = false
            let (host, tab) = makeEditor()
            defer { host.remove(tab) }
            let ed = tab.editor
            ed.markdown = "one\ntwo\n\nfour"
            try expect(!ed.showsLineNumbers, "off by default")
            LineNumberSettings.isEnabled = true
            try expect(ed.showsLineNumbers && ed.lineNumbers.lineCount == 4, "on: \(ed.lineNumbers.lineCount) lines")
            try expect(ed.lineNumbers.ruleThickness > 10, "gutter has width")
            let tv = ed.textView!
            var rng: UInt64 = 0xD1B54A32D192ED03
            func rand(_ n: Int) -> Int { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return Int(rng % UInt64(n)) }
            let pieces = ["\n", "a", "\n\n", "line\nline\n", "é😀", "\r\n", " "]
            for step in 0..<400 {
                let len = tv.string.utf16.count
                if rand(3) == 0, len > 0 {
                    let at = rand(len)
                    tv.insertText("", replacementRange: NSRange(location: at, length: min(len - at, 1 + rand(8))))
                } else {
                    let at = rand(len + 1)
                    tv.insertText(pieces[rand(pieces.count)], replacementRange: NSRange(location: at, length: rand(3) == 0 ? min(len - at, rand(5)) : 0))
                }
                var expected = [0]
                LineNumberRulerView.appendLineStarts(in: tv.string as NSString, range: NSRange(location: 0, length: tv.string.utf16.count), to: &expected)
                try expect(ed.lineNumbers.lineStarts == expected, "step \(step): index diverged")
            }
            ed.markdown = String(repeating: "x\n", count: 12345)
            try expect(ed.lineNumbers.lineCount == 12346, "document replaced: \(ed.lineNumbers.lineCount)")
            // Drawing visible lines works without throwing (smoke test, offscreen).
            ed.view.layoutSubtreeIfNeeded()
            _ = ed.lineNumbers.bitmapImageRepForCachingDisplay(in: ed.lineNumbers.bounds).map { ed.lineNumbers.cacheDisplay(in: ed.lineNumbers.bounds, to: $0) }
            // A new editor created while the setting is on shows the gutter from the start.
            let (host2, tab2) = makeEditor()
            defer { host2.remove(tab2) }
            try expect(tab2.editor.showsLineNumbers, "new editor with setting on")
            LineNumberSettings.isEnabled = false
            try expect(!ed.showsLineNumbers && !tab2.editor.showsLineNumbers, "off again")
        }

        testRunner("Hidden preview is not rendered while typing, and catches up when shown (PERF-003)") {
            let (host, tab) = makeEditor()
            defer { host.remove(tab) }
            let ed = tab.editor
            ed.markdown = "start"
            try settle(ed, after: 0)
            ed.togglePane(.preview)
            try expect(!ed.isPaneVisible(.preview), "preview hidden")
            let renders = ed.renderCount
            ed.textView.insertText(" typed-while-hidden", replacementRange: NSRange(location: 5, length: 0))
            wait(0.5) { false }
            try expect(ed.renderCount == renders, "rendered while hidden: \(ed.renderCount - renders)")
            ed.togglePane(.preview)
            try settle(ed, after: renders)
            try expectContains(try previewHTML(ed), "typed-while-hidden")
        }

        testRunner("Local images load in preview when baseURL is set") {
            let (host, tab) = makeEditor()
            defer { host.remove(tab) }
            let ed = tab.editor
            let projectDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            ed.baseURL = projectDir
            ed.markdown = "<p><img id=\"test_icon\" src=\"Resources/AppIcon.svg\" width=\"128\" height=\"128\"></p>"
            try settle(ed, after: 0)
            var naturalWidth: Int?
            let ok = wait(5) {
                var w: Int?
                ed.webView.evaluateJavaScript("var img = document.getElementById('test_icon'); img && img.complete ? img.naturalWidth : 0") { res, _ in
                    w = res as? Int
                }
                while w == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
                if let nw = w, nw > 0 {
                    naturalWidth = nw
                    return true
                }
                return false
            }
            try expect(ok && (naturalWidth ?? 0) > 0, "local image should load with naturalWidth > 0, got \(String(describing: naturalWidth))")
        }
    }
}
