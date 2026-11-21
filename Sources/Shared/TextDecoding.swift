import Foundation

/// Text decoded from a file, plus what is needed to write it back in the same form.
public struct DecodedText: Equatable {
    public let text: String
    public let encoding: String.Encoding
    public let hasBOM: Bool
    /// Bytes that were not valid UTF-8 in an otherwise UTF-8 file and were read as Windows
    /// Latin 1 instead; saving writes them as UTF-8 (a repair the user is told about).
    public var repairedBytes: Int = 0
}

/// Encoding detection for Markdown files.
///
/// UTF-16 is only used when the file starts with a byte-order mark: without one, almost any byte
/// sequence "decodes" as UTF-16, which turned legacy 8-bit files into garbage that was then saved.
public enum TextDecoding {
    /// Picks the first encoding whose decoding reproduces the original bytes exactly, so opening
    /// and saving a file never changes bytes the user did not edit. Foundation's decoders are
    /// lenient (e.g. a lone 0xA9 "©" in a Latin-1 file decodes as UTF-8 with U+FFFD), so every
    /// candidate is verified by re-encoding. Latin-1 maps every byte and is the final fallback.
    public static func decode(_ data: Data) -> DecodedText {
        let head = [UInt8](data.prefix(3))
        if head.starts(with: [0xEF, 0xBB, 0xBF]), let s = exact(data.dropFirst(3), .utf8) {
            return DecodedText(text: s, encoding: .utf8, hasBOM: true)
        }
        if data.count % 2 == 0 {
            if head.starts(with: [0xFF, 0xFE]), let s = exact(data.dropFirst(2), .utf16LittleEndian) {
                return DecodedText(text: s, encoding: .utf16LittleEndian, hasBOM: true)
            }
            if head.starts(with: [0xFE, 0xFF]), let s = exact(data.dropFirst(2), .utf16BigEndian) {
                return DecodedText(text: s, encoding: .utf16BigEndian, hasBOM: true)
            }
        }
        if let s = exact(data, .utf8) {
            return DecodedText(text: s, encoding: .utf8, hasBOM: false)
        }
        // Mostly UTF-8 with a few stray 8-bit bytes (e.g. one Latin-1 character pasted into a UTF-8
        // file): decoding the whole file as 8-bit would garble every UTF-8 character and saving
        // would double-encode them, so keep UTF-8 and read only the stray bytes as Windows Latin 1.
        let bomless = head.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        if let mixed = mixedUTF8(bomless) {
            return DecodedText(text: mixed.text, encoding: .utf8, hasBOM: bomless.count != data.count,
                               repairedBytes: mixed.repaired)
        }
        if let s = exact(data, .windowsCP1252) {
            return DecodedText(text: s, encoding: .windowsCP1252, hasBOM: false)
        }
        // ISO Latin-1 maps every byte to U+0000–U+00FF and back, so this always round-trips.
        return DecodedText(text: String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self),
                           encoding: .isoLatin1, hasBOM: false)
    }

    /// Decodes `data` only if re-encoding the result gives back exactly the same bytes.
    private static func exact(_ data: Data, _ encoding: String.Encoding) -> String? {
        guard let s = String(data: data, encoding: encoding),
              s.data(using: encoding, allowLossyConversion: false) == data else { return nil }
        return s
    }

    /// UTF-8 decoding that maps invalid bytes through Windows Latin 1. Returns nil unless the data
    /// contains at least one valid multi-byte UTF-8 sequence (otherwise it is a plain 8-bit file).
    private static func mixedUTF8(_ data: Data.SubSequence) -> (text: String, repaired: Int)? {
        let b = [UInt8](data)
        var scalars = String.UnicodeScalarView()
        var valid = 0, repaired = 0, i = 0
        func cp1252(_ x: UInt8) -> Unicode.Scalar {
            if let s = String(data: Data([x]), encoding: .windowsCP1252)?.unicodeScalars.first { return s }
            return Unicode.Scalar(x)
        }
        while i < b.count {
            let x = b[i]
            if x < 0x80 { scalars.append(Unicode.Scalar(x)); i += 1; continue }
            var len = 0, lo: UInt8 = 0x80, hi: UInt8 = 0xBF
            switch x {
            case 0xC2...0xDF: len = 2
            case 0xE0: len = 3; lo = 0xA0
            case 0xE1...0xEC, 0xEE, 0xEF: len = 3
            case 0xED: len = 3; hi = 0x9F
            case 0xF0: len = 4; lo = 0x90
            case 0xF1...0xF3: len = 4
            case 0xF4: len = 4; hi = 0x8F
            default: len = 0
            }
            var ok = len > 0 && i + len <= b.count
            if ok {
                for k in 1..<len {
                    let c = b[i + k]
                    if c < (k == 1 ? lo : 0x80) || c > (k == 1 ? hi : 0xBF) { ok = false; break }
                }
            }
            if ok, let s = String(bytes: b[i..<(i + len)], encoding: .utf8)?.unicodeScalars.first {
                scalars.append(s)
                valid += 1
                i += len
            } else {
                scalars.append(cp1252(x))
                repaired += 1
                i += 1
            }
        }
        guard valid > 0, repaired > 0 else { return nil }
        return (String(scalars), repaired)
    }

    /// Human-readable encoding name for messages.
    public static func name(_ encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case .utf16LittleEndian, .utf16BigEndian: return "UTF-16"
        case .windowsCP1252: return "Windows Latin 1"
        case .isoLatin1: return "ISO Latin 1"
        default: return String.localizedName(of: encoding)
        }
    }

    /// Encodes `text` in the original encoding. If the text can no longer be represented there
    /// (e.g. emoji typed into a Latin-1 file), falls back to UTF-8 and reports it.
    public static func encode(_ text: String, encoding: String.Encoding, hasBOM: Bool) -> (data: Data, encoding: String.Encoding, hasBOM: Bool) {
        if let body = text.data(using: encoding, allowLossyConversion: false) {
            return (bom(encoding, hasBOM) + body, encoding, hasBOM)
        }
        return (Data(text.utf8), .utf8, false)
    }

    private static func bom(_ encoding: String.Encoding, _ hasBOM: Bool) -> Data {
        guard hasBOM else { return Data() }
        switch encoding {
        case .utf8: return Data([0xEF, 0xBB, 0xBF])
        case .utf16LittleEndian: return Data([0xFF, 0xFE])
        case .utf16BigEndian: return Data([0xFE, 0xFF])
        default: return Data()
        }
    }
}
