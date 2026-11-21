import Cocoa
import QuickLookUI
import UniformTypeIdentifiers

/// Data-based Quick Look preview: renders Markdown files (Finder → Space) as GitHub-styled HTML
/// that follows the system light/dark appearance.
@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest,
                        completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void) {
        do {
            let url = request.fileURL
            let (data, truncated) = try Self.readCapped(url)
            var markdown = TextDecoding.decode(data).text
            if truncated {
                markdown += "\n\n---\n\n*Preview truncated: the file is larger than \(Self.maxBytes / 1_000_000) MB.*\n"
            }
            let title = url.deletingPathExtension().lastPathComponent
            // Zero-click context: no remote resources (renderer) and a CSP that forbids script and
            // remote loads, as a second layer in Quick Look's script-enabled web view.
            let body = Markdown.html(from: markdown, allowRemoteResources: false)
            let html = HTMLTemplate.standalone(body: body, title: title, theme: .auto, remoteImages: false)
            let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1100)) { reply in
                reply.stringEncoding = .utf8
                reply.title = url.lastPathComponent
                return Data(html.utf8)
            }
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }

    /// Only the first 10 MB is previewed, so a huge file cannot exhaust the extension's memory.
    static let maxBytes = 10_000_000

    private static func readCapped(_ url: URL) throws -> (Data, Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count > maxBytes else { return (data, false) }
        data = data.prefix(maxBytes)
        // Don't cut a UTF-8 sequence in half (that would push decoding to the 8-bit fallback).
        for _ in 0..<3 where String(data: data, encoding: .utf8) == nil {
            data = data.dropLast()
        }
        return (data, true)
    }
}
