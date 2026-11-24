import Foundation

public enum HTMLTheme {
    /// Follows `prefers-color-scheme`.
    case auto
    case light
    case dark
}

/// Builds full HTML documents around rendered Markdown using a GitHub-style stylesheet.
public enum HTMLTemplate {
    private static let lightVars = """
    --fgColor-default:#1f2328;--fgColor-muted:#59636e;--fgColor-accent:#0969da;\
    --bgColor-default:#ffffff;--bgColor-muted:#f6f8fa;--bgColor-neutral-muted:#818b981f;\
    --bgColor-mark:#fff8c5;--borderColor-default:#d1d9e0;--borderColor-muted:#d1d9e0b3;\
    --fgColor-success:#1a7f37;--fgColor-attention:#9a6700;--fgColor-danger:#d1242f;--fgColor-done:#8250df;\
    color-scheme:light;
    """

    private static let darkVars = """
    --fgColor-default:#f0f6fc;--fgColor-muted:#9198a1;--fgColor-accent:#4493f8;\
    --bgColor-default:#0d1117;--bgColor-muted:#151b23;--bgColor-neutral-muted:#656c7633;\
    --bgColor-mark:#bb800926;--borderColor-default:#3d444d;--borderColor-muted:#3d444db3;\
    --fgColor-success:#3fb950;--fgColor-attention:#d29922;--fgColor-danger:#f85149;--fgColor-done:#ab7df8;\
    color-scheme:dark;
    """

    static let mono = #"ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,"Liberation Mono",monospace"#

    /// GitHub markdown styles (light/dark), parameterised by CSS custom properties.
    public static let css: String = """
    :root{\(lightVars)}
    @media (prefers-color-scheme: dark){:root:not(.light){\(darkVars)}}
    :root.dark{\(darkVars)}
    html,body{margin:0;padding:0;background-color:var(--bgColor-default);}
    .markdown-body{-webkit-text-size-adjust:100%;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Noto Sans",Helvetica,Arial,sans-serif,"Apple Color Emoji","Segoe UI Emoji";font-size:16px;line-height:1.5;word-wrap:break-word;color:var(--fgColor-default);background-color:var(--bgColor-default);box-sizing:border-box;max-width:980px;margin:0 auto;padding:32px 45px;}
    .markdown-body>*:first-child{margin-top:0!important}
    .markdown-body>*:last-child{margin-bottom:0!important}
    .markdown-body a{color:var(--fgColor-accent);text-decoration:none}
    .markdown-body a:hover{text-decoration:underline}
    .markdown-body strong,.markdown-body b{font-weight:600}
    .markdown-body p,.markdown-body blockquote,.markdown-body ul,.markdown-body ol,.markdown-body dl,.markdown-body table,.markdown-body pre,.markdown-body details,.markdown-body .markdown-alert{margin-top:0;margin-bottom:16px}
    .markdown-body h1,.markdown-body h2,.markdown-body h3,.markdown-body h4,.markdown-body h5,.markdown-body h6{margin-top:24px;margin-bottom:16px;font-weight:600;line-height:1.25}
    .markdown-body h1{font-size:2em;padding-bottom:.3em;border-bottom:1px solid var(--borderColor-muted)}
    .markdown-body h2{font-size:1.5em;padding-bottom:.3em;border-bottom:1px solid var(--borderColor-muted)}
    .markdown-body h3{font-size:1.25em}
    .markdown-body h4{font-size:1em}
    .markdown-body h5{font-size:.875em}
    .markdown-body h6{font-size:.85em;color:var(--fgColor-muted)}
    .markdown-body hr{box-sizing:content-box;height:.25em;padding:0;margin:24px 0;background-color:var(--borderColor-default);border:0;overflow:hidden}
    .markdown-body blockquote{margin-left:0;margin-right:0;padding:0 1em;color:var(--fgColor-muted);border-left:.25em solid var(--borderColor-default)}
    .markdown-body blockquote blockquote blockquote blockquote{padding:0 0 0 .5em}
    .markdown-body blockquote>:first-child{margin-top:0}
    .markdown-body blockquote>:last-child{margin-bottom:0}
    .markdown-body ul,.markdown-body ol{padding-left:2em}
    .markdown-body ol ol,.markdown-body ul ol{list-style-type:lower-roman}
    .markdown-body ul ul ol,.markdown-body ul ol ol,.markdown-body ol ul ol,.markdown-body ol ol ol{list-style-type:lower-alpha}
    .markdown-body ul ul,.markdown-body ul ol,.markdown-body ol ol,.markdown-body ol ul{margin-top:0;margin-bottom:0}
    .markdown-body li>p{margin-top:16px}
    .markdown-body li+li{margin-top:.25em}
    .markdown-body .task-list-item{list-style-type:none}
    .markdown-body .task-list-item+.task-list-item{margin-top:.25em}
    .markdown-body .task-list-item-checkbox{margin:0 .2em .25em -1.4em;vertical-align:middle}
    .markdown-body code,.markdown-body kbd,.markdown-body pre,.markdown-body samp,.markdown-body tt{font-family:\(mono)}
    .markdown-body code,.markdown-body tt{padding:.2em .4em;margin:0;font-size:85%;white-space:break-spaces;background-color:var(--bgColor-neutral-muted);border-radius:6px}
    .markdown-body pre{padding:16px;overflow:auto;font-size:85%;line-height:1.45;color:var(--fgColor-default);background-color:var(--bgColor-muted);border-radius:6px;word-wrap:normal}
    .markdown-body pre code{display:inline;padding:0;margin:0;overflow:visible;line-height:inherit;word-wrap:normal;background-color:transparent;border:0;font-size:100%;white-space:pre;word-break:normal}
    .markdown-body table{border-spacing:0;border-collapse:collapse;display:block;width:max-content;max-width:100%;overflow:auto;font-variant:tabular-nums}
    .markdown-body table th{font-weight:600}
    .markdown-body table th,.markdown-body table td{padding:6px 13px;border:1px solid var(--borderColor-default)}
    .markdown-body table tr{background-color:var(--bgColor-default);border-top:1px solid var(--borderColor-muted)}
    .markdown-body table tr:nth-child(2n){background-color:var(--bgColor-muted)}
    .markdown-body img{max-width:100%;box-sizing:content-box;border-style:none}
    .markdown-body kbd{display:inline-block;padding:3px 5px;font:11px \(mono);line-height:10px;color:var(--fgColor-default);vertical-align:middle;background-color:var(--bgColor-muted);border:solid 1px var(--borderColor-muted);border-radius:6px;box-shadow:inset 0 -1px 0 var(--borderColor-muted)}
    .markdown-body mark{background-color:var(--bgColor-mark);color:var(--fgColor-default)}
    .markdown-body sup,.markdown-body sub{font-size:75%;line-height:0;position:relative;vertical-align:baseline}
    .markdown-body sup{top:-.5em}
    .markdown-body sub{bottom:-.25em}
    .markdown-body details summary{cursor:pointer}
    .markdown-body dl{padding:0}
    .markdown-body dl dt{padding:0;margin-top:16px;font-size:1em;font-style:italic;font-weight:600}
    .markdown-body dl dd{padding:0 16px;margin-bottom:16px}
    .markdown-body .markdown-alert{padding:.5rem 1rem;color:inherit;border-left:.25em solid var(--borderColor-default)}
    .markdown-body .markdown-alert>:first-child{margin-top:0}
    .markdown-body .markdown-alert>:last-child{margin-bottom:0}
    .markdown-body .markdown-alert .markdown-alert-title{display:flex;font-weight:500;align-items:center;line-height:1}
    .markdown-body .markdown-alert-title svg{margin-right:.5rem;fill:currentColor}
    .markdown-body .markdown-alert-note{border-left-color:var(--fgColor-accent)}
    .markdown-body .markdown-alert-note .markdown-alert-title{color:var(--fgColor-accent)}
    .markdown-body .markdown-alert-tip{border-left-color:var(--fgColor-success)}
    .markdown-body .markdown-alert-tip .markdown-alert-title{color:var(--fgColor-success)}
    .markdown-body .markdown-alert-important{border-left-color:var(--fgColor-done)}
    .markdown-body .markdown-alert-important .markdown-alert-title{color:var(--fgColor-done)}
    .markdown-body .markdown-alert-warning{border-left-color:var(--fgColor-attention)}
    .markdown-body .markdown-alert-warning .markdown-alert-title{color:var(--fgColor-attention)}
    .markdown-body .markdown-alert-caution{border-left-color:var(--fgColor-danger)}
    .markdown-body .markdown-alert-caution .markdown-alert-title{color:var(--fgColor-danger)}
    .markdown-body .footnotes{font-size:12px;color:var(--fgColor-muted);border-top:1px solid var(--borderColor-default);padding-top:8px;margin-top:24px}
    .markdown-body .footnotes ol{padding-left:16px}
    .markdown-body .footnotes li:target{color:var(--fgColor-default)}
    .markdown-body .footnote-backref{font-family:-apple-system,sans-serif}
    @media (max-width:767px){.markdown-body{padding:16px}}
    @media print{
      html,body{background:#fff;-webkit-print-color-adjust:exact;print-color-adjust:exact}
      .markdown-body{max-width:none;padding:0;font-size:12pt}
      .markdown-body pre,.markdown-body pre code{white-space:pre-wrap;word-break:break-word}
      .markdown-body h1,.markdown-body h2,.markdown-body h3,.markdown-body h4{break-after:avoid}
      .markdown-body pre,.markdown-body blockquote,.markdown-body table,.markdown-body img,.markdown-body tr{break-inside:avoid}
      .markdown-body table{display:table}
    }
    """

    /// Simplified light stylesheet without CSS variables, used for rich text (RTF/ODT/DOCX/clipboard)
    /// conversion where the HTML importer does not handle modern CSS well.
    public static let richCSS: String = """
    body{font-family:-apple-system,"Helvetica Neue",Helvetica,Arial,sans-serif;font-size:12pt;line-height:1.4;color:#1f2328;}
    h1{font-size:22pt;font-weight:600;margin:14pt 0 8pt}
    h2{font-size:17pt;font-weight:600;margin:12pt 0 6pt}
    h3{font-size:14pt;font-weight:600;margin:10pt 0 6pt}
    h4{font-size:12pt;font-weight:600;margin:10pt 0 4pt}
    h5{font-size:11pt;font-weight:600;margin:8pt 0 4pt}
    h6{font-size:10.5pt;font-weight:600;color:#59636e;margin:8pt 0 4pt}
    p,ul,ol,blockquote,pre,table{margin:0 0 8pt}
    a{color:#0969da}
    code{font-family:Menlo,monospace;font-size:10.5pt;background-color:#eff1f3}
    pre{font-family:Menlo,monospace;font-size:10pt;background-color:#f6f8fa;padding:8pt}
    pre code{background-color:transparent}
    blockquote{color:#59636e;border-left:3pt solid #d1d9e0;padding-left:8pt;margin-left:0}
    table{border-collapse:collapse}
    th,td{border:1px solid #d1d9e0;padding:3pt 6pt}
    th{font-weight:600;background-color:#f6f8fa}
    hr{border:0;border-top:2pt solid #d1d9e0}
    .markdown-alert-title{font-weight:600}
    .markdown-alert-title svg{display:none}
    """

    /// Content Security Policy for rendered documents: never any script, frame, form or plugin;
    /// images from the web only when `remoteImages` is true.
    public static func csp(remoteImages: Bool) -> String {
        "default-src 'none'; style-src 'unsafe-inline'; font-src data:; img-src data: file:\(remoteImages ? " http: https:" : ""); "
            + "script-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'"
    }

    /// `remoteImages`: false for zero-click contexts (Quick Look), where a remote image would tell
    /// the document's author that the file was looked at.
    public static func standalone(body: String, title: String, theme: HTMLTheme, remoteImages: Bool = true) -> String {
        let cls: String
        switch theme {
        case .auto: cls = ""
        case .light: cls = " class=\"light\""
        case .dark: cls = " class=\"dark\""
        }
        return """
        <!DOCTYPE html>
        <html lang="en"\(cls)>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp(remoteImages: remoteImages))">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="\(theme == .auto ? "light dark" : theme == .dark ? "dark" : "light")">
        <title>\(MDEscape.html(title))</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)</article>
        </body>
        </html>
        """
    }

    public static func richDocument(body: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(MDEscape.html(title))</title>
        <style>\(richCSS)</style></head>
        <body>\(body)</body></html>
        """
    }

    /// Empty preview page; content is injected into `#content` by the editor.
    public static func previewShell(dark: Bool, baseHref: String? = nil) -> String {
        let baseTag = baseHref.map { "<base href=\"\(MDEscape.attr($0))\">\n" } ?? ""
        return """
        <!DOCTYPE html>
        <html lang="en" class="\(dark ? "dark" : "light")">
        <head>
        <meta charset="utf-8">
        \(baseTag)<style>
        \(css)
        .markdown-body{min-height:100vh}
        </style>
        </head>
        <body>
        <article id="content" class="markdown-body"></article>
        </body>
        </html>
        """
    }
}
