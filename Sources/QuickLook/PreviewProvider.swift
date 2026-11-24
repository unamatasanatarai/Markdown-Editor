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
            let inlinedBody = Self.inlineLocalImages(in: body, relativeTo: url.deletingLastPathComponent())
            let html = HTMLTemplate.standalone(body: inlinedBody, title: title, theme: .auto, remoteImages: false)
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

    /// Inlines local relative images as base64 data URIs so Quick Look's isolated web view
    /// can render them without needing local filesystem access or network access.
    static func inlineLocalImages(in html: String, relativeTo baseDir: URL) -> String {
        let pattern = #"(<img\b[^>]*?\bsrc=["'])([^"']+)(["'][^>]*>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return html }
        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return html }

        var result = ""
        var lastIndex = 0

        for match in matches {
            let fullRange = match.range
            let prefixRange = match.range(at: 1)
            let srcRange = match.range(at: 2)
            let suffixRange = match.range(at: 3)

            if fullRange.location > lastIndex {
                result += nsString.substring(with: NSRange(location: lastIndex, length: fullRange.location - lastIndex))
            }
            lastIndex = fullRange.location + fullRange.length

            let prefix = nsString.substring(with: prefixRange)
            let src = nsString.substring(with: srcRange)
            let suffix = nsString.substring(with: suffixRange)

            let lower = src.lowercased()
            if lower.hasPrefix("data:") || lower.hasPrefix("http:") || lower.hasPrefix("https:") || lower.hasPrefix("//") {
                result += prefix + src + suffix
                continue
            }

            let decodedPath = src.removingPercentEncoding ?? src
            let imgURL: URL
            if decodedPath.hasPrefix("/") {
                imgURL = URL(fileURLWithPath: decodedPath)
            } else {
                imgURL = baseDir.appendingPathComponent(decodedPath).standardizedFileURL
            }

            // Cap individual inlined images to 10 MB to prevent exhausting memory.
            if let data = try? Data(contentsOf: imgURL), data.count <= 10_000_000 {
                let mime = mimeType(for: imgURL.pathExtension)
                let dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
                result += prefix + dataURI + suffix
            } else {
                result += prefix + src + suffix
            }
        }

        if lastIndex < nsString.length {
            result += nsString.substring(with: NSRange(location: lastIndex, length: nsString.length - lastIndex))
        }

        return result
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "bmp": return "image/bmp"
        case "tif", "tiff": return "image/tiff"
        case "heic": return "image/heic"
        case "avif": return "image/avif"
        default: return "application/octet-stream"
        }
    }

    /// Only the first 10 MB is previewed, so a huge file cannot exhaust the extension's memory.
    static let maxBytes = 10_000_000

    private static func readCapped(_ url: URL) throws -> (Data, Bool) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        var data: Data
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            data = (try? handle.read(upToCount: maxBytes + 1)) ?? Data()
        } else {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        }
        guard data.count > maxBytes else { return (data, false) }
        data = data.prefix(maxBytes)
        // Don't cut a UTF-8 sequence in half (that would push decoding to the 8-bit fallback).
        for _ in 0..<3 where String(data: data, encoding: .utf8) == nil {
            data = data.dropLast()
        }
        return (data, true)
    }
}
