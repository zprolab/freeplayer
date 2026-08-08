import Foundation

struct LyricLine: Identifiable, Equatable {
    var id: Int { time.hashValue }
    var time: Double
    var text: String
}

enum LRC {

    // Parse raw LRC text into sorted, deduped lyric lines.
    // Handles [mm:ss.xx]text, [mm:ss]text, multi-timestamp lines, metadata tags.
    static func parse(_ raw: String?) -> [LyricLine] {
        guard let raw, !raw.isEmpty else { return [] }
        var entries: [LyricLine] = []

        let lines = raw.components(separatedBy: .newlines)
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            var times: [Double] = []
            var scanIndex = trimmed.startIndex
            let pattern = "\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"
            while let range = trimmed.range(of: pattern, options: .regularExpression, range: scanIndex..<trimmed.endIndex) {
                let tag = String(trimmed[range])
                scanIndex = range.upperBound
                let parts = tag.dropFirst().dropLast().split(separator: ":", maxSplits: 1)
                guard let m = Int(parts[0]), let s = Int(parts[1].prefix(2)) else { continue }
                var cs = 0.0
                let fracPart = parts[1].dropFirst(2)
                if !fracPart.isEmpty {
                    let c = Int(fracPart.prefix(2)) ?? 0
                    cs = Double(c) / 100.0
                }
                times.append(Double(m * 60) + Double(s) + cs)
            }
            if times.isEmpty { continue }

            guard let lastBracket = trimmed.lastIndex(of: "]") else { continue }
            let textStart = trimmed.index(after: lastBracket)
            let text = sanitize(String(trimmed[textStart...]).trimmingCharacters(in: .whitespaces))
            if text.isEmpty { continue }

            for time in times {
                entries.append(LyricLine(time: time, text: text))
            }
        }

        entries.sort { $0.time < $1.time }
        var deduped: [LyricLine] = []
        for e in entries {
            if let last = deduped.last, last.text == e.text { continue }
            deduped.append(e)
        }
        return deduped
    }

    // Replace control / invisible / non-renderable glyphs with spaces.
    static func sanitize(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            let cp = scalar.value
            if cp <= 0x08 || cp == 0x0B || cp == 0x0C
                || (cp >= 0x0E && cp <= 0x1F)
                || (cp >= 0x7F && cp <= 0x9F)
                || (cp >= 0x200B && cp <= 0x200F)
                || (cp >= 0x2028 && cp <= 0x202E)
                || (cp >= 0x2060 && cp <= 0x206F)
                || cp == 0xFEFF || cp == 0xFFFD {
                result.append(" ")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    // Read an .lrc file, auto-detecting CJK encodings (UTF-8 → GB18030 → others).
    static func read(path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        if let s = String(data: data, encoding: .utf8) { return s }
        let fallbacks: [String.Encoding] = [
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
            .shiftJIS,
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS_X0213.rawValue))),
        ]
        for enc in fallbacks {
            if let s = String(data: data, encoding: enc) { return s }
        }
        return nil
    }
}
