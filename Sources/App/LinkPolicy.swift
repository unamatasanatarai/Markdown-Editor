import Foundation

/// What to do when a link in the preview is clicked.
///
/// Documents are untrusted: a README can link to `tools/setup.command` or an `.app` bundle next to
/// it (files from `git clone` carry no quarantine flag), or to a custom URL scheme that launches
/// another app. Only web and mail links open directly; local Markdown files open in this editor;
/// any other local file is revealed in Finder instead of being launched; other schemes need
/// confirmation.
enum LinkAction: Equatable {
    case openExternally(URL)
    case openDocument(URL)
    case revealInFinder(URL)
    case confirm(URL)
}

enum LinkPolicy {
    static let documentExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtext", "txt"]

    static func action(for url: URL) -> LinkAction {
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto":
            return .openExternally(url)
        case "file":
            return documentExtensions.contains(url.pathExtension.lowercased()) ? .openDocument(url) : .revealInFinder(url)
        default:
            return .confirm(url)
        }
    }
}
