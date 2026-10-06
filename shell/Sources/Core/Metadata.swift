// FreePlayer shell — audio metadata extraction via AVFoundation
// Replaces music-metadata (electron). Synchronous (semaphore) so the
// import loop stays simple; call from a background queue.

import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

/// Box so concurrently-executing code may mutate the payload without tripping
/// the Swift 5.10 strict-concurrency check (same pattern as ImportPipeline).
private final class Box<T> {
    var value: T
    init(_ v: T) { value = v }
}

enum Metadata {

    static let gb18030: String.Encoding = {
        let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String.Encoding(rawValue: cf)
    }()

    private static func firstValue(_ items: [AVMetadataItem], _ key: AVMetadataKey) async -> String? {
        for it in items where it.commonKey == key {
            if let v = try? await it.load(.stringValue) {
                let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    // Strip downloader suffixes: "Artist - Title_EM.flac" -> "Artist - Title"
    private static let stemSuffixRegex: NSRegularExpression = {
        // M9: compile once, not per call (import loop + every getLrc sidecar lookup)
        try! NSRegularExpression(pattern: "_[A-Za-z]{1,4}$")
    }()

    static func cleanAudioStem(_ stem: String) -> String {
        stemSuffixRegex.stringByReplacingMatches(
            in: stem, options: [], range: NSRange(location: 0, length: (stem as NSString).length),
            withTemplate: "")
    }

    // Try to find a sidecar .lrc for an audio file (same dir, same stem,
    // tolerant of _EM/_L downloader suffixes and prefix-style names).
    static func findSidecarLrc(_ audioPath: String) -> String? {
        let dir = (audioPath as NSString).deletingLastPathComponent
        let audioStem = cleanAudioStem(((audioPath as NSString).lastPathComponent as NSString).deletingPathExtension)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        var candidates: [(stem: String, name: String)] = []
        for name in names {
            if (name as NSString).pathExtension.lowercased() == "lrc" {
                let stem = cleanAudioStem((name as NSString).deletingPathExtension)
                if stem == audioStem { return (dir as NSString).appendingPathComponent(name) } // exact match wins
                candidates.append((stem, name))
            }
        }
        // Prefix match: "Welcome Home" is a prefix of "Welcome Home, Son (Remaster)".
        // Auto-fetched sidecars are "<stem>.<trackId>.lrc" — a numeric suffix must
        // never prefix-match a sibling track, so skip ".<digits>" stems here.
        for pair in candidates {
            if pair.stem.range(of: "\\.[0-9]+$", options: .regularExpression) != nil { continue }
            let a = audioStem.lowercased()
            let s = pair.stem.lowercased()
            let minLen = Swift.min(a.count, s.count)
            if minLen >= 8 && s.hasPrefix(a) {
                return (dir as NSString).appendingPathComponent(pair.name)
            }
        }
        return nil
    }

    // Parse the FLAC metadata blocks AVFoundation does not surface: the
    // VORBIS_COMMENT block (tags, incl. LYRICS) and the PICTURE block (cover
    // art). One pass over the block headers; every read is bounded by the
    // bytes actually present, so a crafted file cannot make it spin.
    private static func parseFlacBlocks(_ path: String) -> (tags: [String: String]?, picture: Data?) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count >= 4, Array(data.prefix(4)) == [0x66, 0x4C, 0x61, 0x43] /* "fLaC" */ else {
            return (nil, nil)
        }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> ([String: String]?, Data?) in
            guard let base = raw.baseAddress else { return (nil, nil) }
            var p = base.assumingMemoryBound(to: UInt8.self) + 4
            var remaining = data.count - 4
            var tags: [String: String]?
            var picture: Data?
            var pictureType = -1
            while remaining >= 4 {
                let blockHeader = p[0]
                let type = Int(blockHeader & 0x7f)
                let len = (UInt32(p[1]) << 16) | (UInt32(p[2]) << 8) | UInt32(p[3])
                p += 4; remaining -= 4
                if remaining < Int(len) { break }
                if type == 4 { // VORBIS_COMMENT
                    tags = parseVorbisCommentBlock(p, Int(len)) ?? tags
                } else if type == 6 { // PICTURE
                    if let (art, kind) = parseFlacPictureBlock(p, Int(len)),
                       picture == nil || (kind == 3 && pictureType != 3) {
                        // Prefer the front cover (type 3); otherwise the first
                        // picture the file offers.
                        picture = art
                        pictureType = kind
                    }
                }
                p += Int(len); remaining -= Int(len)
            }
            return (tags, picture)
        }
    }

    /// VORBIS_COMMENT block body: vendor string, then length-prefixed
    /// "KEY=value" entries (all lengths 4-byte little-endian).
    private static func parseVorbisCommentBlock(_ p: UnsafePointer<UInt8>, _ len: Int) -> [String: String]? {
        var c = p
        var cRem = len
        // vendor string (4-byte LE length + data)
        if cRem < 4 { return nil }
        let vendorLen = UInt32(c[0]) | (UInt32(c[1]) << 8) | (UInt32(c[2]) << 16) | (UInt32(c[3]) << 24)
        c += 4; cRem -= 4
        if cRem < Int(vendorLen) { return nil }
        c += Int(vendorLen); cRem -= Int(vendorLen)
        if cRem < 4 { return nil }
        let count = UInt32(c[0]) | (UInt32(c[1]) << 8) | (UInt32(c[2]) << 16) | (UInt32(c[3]) << 24)
        c += 4; cRem -= 4
        var tags: [String: String] = [:]
        // Bound by remaining bytes, not the file-declared `count`: a crafted
        // FLAC can claim 0xFFFFFFFF comments over a short block, and
        // `where cRem >= 4` turned every remaining iteration into a no-op spin
        // (~4.3B) — an import hang.
        for _ in 0..<count {
            if cRem < 4 { break }
            let clen = UInt32(c[0]) | (UInt32(c[1]) << 8) | (UInt32(c[2]) << 16) | (UInt32(c[3]) << 24)
            c += 4; cRem -= 4
            if cRem < Int(clen) { break }
            guard let entry = String(bytes: UnsafeBufferPointer(start: c, count: Int(clen)), encoding: .utf8) else {
                c += Int(clen); cRem -= Int(clen); continue
            }
            c += Int(clen); cRem -= Int(clen)
            if let eq = entry.range(of: "=") {
                let key = entry[..<eq.lowerBound].lowercased()
                let value = String(entry[eq.upperBound...])
                if !key.isEmpty && !value.isEmpty { tags[key] = value }
            }
        }
        return tags.isEmpty ? nil : tags
    }

    /// PICTURE block body (all fields big-endian): picture type(4) |
    /// MIME(4+len) | description(4+len) | width(4) height(4) depth(4)
    /// colors(4) | data length(4) | data. Returns the image bytes and the
    /// picture type, or nil when the block is malformed.
    private static func parseFlacPictureBlock(_ p: UnsafePointer<UInt8>, _ len: Int) -> (Data, Int)? {
        func u32(_ at: Int) -> Int? {
            guard at >= 0, at + 4 <= len else { return nil }
            return Int((UInt32(p[at]) << 24) | (UInt32(p[at + 1]) << 16)
                | (UInt32(p[at + 2]) << 8) | UInt32(p[at + 3]))
        }
        guard let kind = u32(0), let mimeLen = u32(4) else { return nil }
        var cursor = 8 + mimeLen
        guard let descLen = u32(cursor) else { return nil }
        cursor += 4 + descLen
        guard cursor + 16 <= len, let dataLen = u32(cursor + 16), dataLen > 0 else { return nil }
        cursor += 20
        guard cursor + dataLen <= len else { return nil }
        return (Data(bytes: p + cursor, count: dataLen), kind)
    }

    // Decode an ID3v2 string body given its encoding byte. Encoding:
    // 0=ISO-8859-1 (often actually GBK for CJK tags), 1=UTF-16 w/ BOM,
    // 2=UTF-16BE, 3=UTF-8.
    private static func decodeId3String(_ text: UnsafePointer<UInt8>, _ len: Int, _ enc: UInt8) -> String {
        var textLen = len
        if textLen <= 0 { return "" }
        if enc == 0 {
            var high = 0
            for i in 0..<textLen where text[i] > 0x7F { high += 1 }
            if textLen > 0, high * 10 > textLen * 3 {
                // Mostly high bytes -> likely GBK mislabeled as Latin-1
                if let gb = String(bytes: UnsafeBufferPointer(start: text, count: textLen), encoding: gb18030),
                   !gb.contains("\u{FFFD}") {
                    return gb
                }
            }
            return String(bytes: UnsafeBufferPointer(start: text, count: textLen), encoding: .isoLatin1) ?? ""
        }
        if enc == 1 {
            if textLen >= 2 && text[textLen - 1] == 0 && text[textLen - 2] == 0 { textLen -= 2 }
            return String(bytes: UnsafeBufferPointer(start: text, count: textLen), encoding: .utf16) ?? ""
        }
        if enc == 2 {
            return String(bytes: UnsafeBufferPointer(start: text, count: textLen), encoding: .utf16BigEndian) ?? ""
        }
        return String(bytes: UnsafeBufferPointer(start: text, count: textLen), encoding: .utf8) ?? ""
    }

    /// Decode an ID3v2 text frame (encoding byte + text).
    private static func decodeId3Text(_ p: UnsafePointer<UInt8>, _ len: UInt32) -> String {
        if len == 0 { return "" }
        return decodeId3String(p + 1, Int(len) - 1, p[0])
    }

    /// Advance `i` past a NUL-terminated string body. UTF-16 bodies terminate
    /// on a 2-byte NUL, so those are scanned two bytes at a time — scanning
    /// byte-wise would stop at the high byte of any ASCII UTF-16 character.
    private static func skipTerminator(_ p: UnsafePointer<UInt8>, _ len: Int, _ i: inout Int, _ enc: UInt8) {
        if enc == 1 || enc == 2 {
            while i + 1 < len {
                if p[i] == 0 && p[i + 1] == 0 { i += 2; return }
                i += 2
            }
            i = len
            return
        }
        while i < len {
            if p[i] == 0 { i += 1; return }
            i += 1
        }
    }

    /// ID3 USLT (unsynchronized lyrics): encoding(1) | language(3) |
    /// content descriptor (terminated) | lyrics text.
    private static func decodeId3USLT(_ p: UnsafePointer<UInt8>, _ len: UInt32) -> String? {
        let n = Int(len)
        guard n > 5 else { return nil }
        let enc = p[0]
        var i = 4
        skipTerminator(p, n, &i, enc)
        guard i < n else { return nil }
        let text = decodeId3String(p + i, n - i, enc)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// ID3 SYLT (synchronized lyrics): encoding(1) | language(3) |
    /// timestamp format(1) | content type(1) | descriptor (terminated) |
    /// (text (terminated) + timestamp u32 BE ms)*. Rendered as LRC so the
    /// player's existing parser reads it exactly like a sidecar file.
    private static func decodeId3SYLT(_ p: UnsafePointer<UInt8>, _ len: UInt32) -> String? {
        let n = Int(len)
        guard n > 6 else { return nil }
        let enc = p[0]
        var i = 6
        skipTerminator(p, n, &i, enc)
        var lines: [String] = []
        while i + 4 <= n {
            let start = i
            skipTerminator(p, n, &i, enc)
            if i > n { break }
            var end = enc == 1 || enc == 2 ? i - 2 : i - 1
            if end < start { end = start }
            guard i + 4 <= n else { break }
            let ms = (UInt32(p[i]) << 24) | (UInt32(p[i + 1]) << 16)
                | (UInt32(p[i + 2]) << 8) | UInt32(p[i + 3])
            i += 4
            let text = decodeId3String(p + start, end - start, enc)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            let total = Int(ms / 1000)
            let centis = Int((ms % 1000) / 10)
            lines.append(String(format: "[%02d:%02d.%02d]%@", total / 60, total % 60, centis, text))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // Parse ID3v2 (v2.3/v2.4) text frames from an MP3 file.
    private static func parseId3v2(_ path: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count >= 10, Array(data.prefix(3)) == [0x49, 0x44, 0x33] /* "ID3" */ else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [String: String]? in
            guard let base = raw.baseAddress else { return nil }
            var p = base.assumingMemoryBound(to: UInt8.self)
            let ver = p[3]
            if ver != 3 && ver != 4 { return nil }
            let tagSize = (UInt32(p[6] & 0x7f) << 21) | (UInt32(p[7] & 0x7f) << 14)
                | (UInt32(p[8] & 0x7f) << 7) | UInt32(p[9] & 0x7f)
            var tagSizeI = Int(tagSize)
            if tagSizeI > data.count - 10 { tagSizeI = data.count - 10 }
            let end = p + 10 + tagSizeI
            p += 10
            // S10: the extended-header block must fit inside the tag — p[5] is only
            // readable when 10 bytes remain, and p += 10 + extSize must not jump past
            // `end`. Malformed headers are skipped gracefully (tags stay readable).
            if p + 10 <= end, (p[5] & 0x40) != 0 { // extended header
                let extSize: Int
                if ver == 4 {
                    extSize = Int((UInt32(p[6] & 0x7f) << 21) | (UInt32(p[7] & 0x7f) << 14)
                        | (UInt32(p[8] & 0x7f) << 7) | UInt32(p[9] & 0x7f))
                } else {
                    extSize = Int((UInt32(p[6]) << 24) | (UInt32(p[7]) << 16) | (UInt32(p[8]) << 8) | UInt32(p[9]))
                }
                if p + 10 + extSize > end {
                    return nil // malformed — treat the whole tag as unreadable
                }
                p += 10 + extSize
            }
            var tags: [String: String] = [:]
            while p + 10 <= end {
                let id = String(bytes: UnsafeBufferPointer(start: p, count: 4), encoding: .ascii) ?? ""
                let size: UInt32
                if ver == 4 {
                    size = (UInt32(p[4] & 0x7f) << 21) | (UInt32(p[5] & 0x7f) << 14)
                        | (UInt32(p[6] & 0x7f) << 7) | UInt32(p[7] & 0x7f)
                } else {
                    size = (UInt32(p[4]) << 24) | (UInt32(p[5]) << 16) | (UInt32(p[6]) << 8) | UInt32(p[7])
                }
                let frame = p + 10
                if frame + Int(size) > end { break }
                if size > 0 {
                    if id == "USLT" {
                        if let lyrics = decodeId3USLT(frame, size) { tags["lyrics"] = lyrics }
                    } else if id == "SYLT" {
                        // Unsynced lyrics win when both frames are present.
                        if tags["lyrics"] == nil, let lyrics = decodeId3SYLT(frame, size) {
                            tags["lyrics"] = lyrics
                        }
                    } else if id.hasPrefix("T") {
                        let value = decodeId3Text(frame, size)
                        switch id {
                        case "TIT2": tags["title"] = value
                        case "TPE1": tags["artist"] = value
                        case "TALB": tags["album"] = value
                        case "TYER", "TDRC": tags["year"] = value
                        case "TCON": tags["genre"] = value
                        case "TRCK": tags["track"] = value
                        case "TPOS": tags["disc"] = value
                        default: break
                        }
                    }
                }
                p = frame + Int(size)
            }
            return tags.isEmpty ? nil : tags
        }
    }

    // MARK: - File baseline: lyrics + cover

    /// Vorbis comment keys that carry lyrics, most specific first: `LYRICS` is
    /// the usual convention, `UNSYNCEDLYRICS` is what foobar2000 writes.
    private static let vorbisLyricsKeys = ["lyrics", "unsyncedlyrics", "unsynced lyrics"]

    /// Pick lyrics out of a FLAC Vorbis comment block.
    static func lyricsFromVorbisTags(_ tags: [String: String]) -> String? {
        for key in vorbisLyricsKeys {
            if let v = tags[key], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return v
            }
        }
        return nil
    }

    /// Lyrics carried by the file itself, for the formats AVFoundation hides
    /// (FLAC Vorbis comments) or file layouts it does not map (ID3 USLT/SYLT).
    /// M4A/©lyr and ID3-through-AVFoundation are read in extractAsync, which
    /// has the asset loaded.
    static func readEmbeddedLyrics(atPath path: String) -> String? {
        switch (path as NSString).pathExtension.lowercased() {
        case "flac": return parseFlacBlocks(path).tags.flatMap(lyricsFromVorbisTags)
        case "mp3": return parseId3v2(path)?["lyrics"]
        default: return nil
        }
    }

    /// Cover art carried by the file itself, for the one layout AVFoundation
    /// does not expose: a FLAC PICTURE block (MP3 APIC and M4A covr arrive
    /// through AVFoundation's commonKeyArtwork in extractAsync).
    static func readEmbeddedCover(atPath path: String) -> Data? {
        guard (path as NSString).pathExtension.lowercased() == "flac" else { return nil }
        return parseFlacBlocks(path).picture
    }

    /// Materialize embedded artwork at the album's shared
    /// `.covers/cover.jpg` and return the path to record. The import pipeline
    /// and the "reset from file" flow both use this, so a track keeps one
    /// cover path whichever way the file's artwork is (re)applied.
    static func writeEmbeddedCover(_ data: Data, audioPath: String) -> String? {
        let dir = ((audioPath as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent(".covers")
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        let coverPath = (dir as NSString).appendingPathComponent("cover.jpg")
        if fm.fileExists(atPath: coverPath) { return coverPath }
        do {
            try data.write(to: URL(fileURLWithPath: coverPath), options: .atomic)
            return coverPath
        } catch {
            NSLog("[metadata] cover write failed: %@", "\(error)")
            return nil
        }
    }

    /// Extract everything the import pipeline needs.
    /// Returns nil if the asset cannot be loaded within 10s (M10: the timeout is
    /// the only failure signal — the load error is intentionally not surfaced;
    /// on timeout the caller falls back to filename-derived tags).
    /// Call on a background queue. Sync facade over the modern async AVFoundation
    /// load(_:) API (deprecated loadValuesAsynchronously/commonMetadata/value).
    static func extractAtPath(_ path: String) -> [String: Any]? {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url, options: nil)
        let sem = DispatchSemaphore(value: 0)
        // Box so the detached task may mutate the payload without tripping the
        // Swift 5.10 strict-concurrency check ("mutation of captured var in
        // concurrently-executing code") — same pattern as ImportPipeline.
        let box = Box<[String: Any]?>(nil)
        Task.detached {
            box.value = await Self.extractAsync(asset: asset, path: path)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 10)
        return box.value
    }

    private static func extractAsync(asset: AVURLAsset, path: String) async -> [String: Any]? {
        // M10: a load failure is the only failure signal — on timeout or error
        // the caller falls back to filename-derived tags.
        guard let (meta, duration, tracks) = try? await asset.load(.commonMetadata, .duration, .tracks) else {
            return nil
        }

        // FLAC: pull the Vorbis comment + PICTURE blocks manually
        // (AVFoundation surfaces neither)
        let ext = (path as NSString).pathExtension.lowercased()
        let vorbis = ext == "flac" ? parseFlacBlocks(path).tags : nil
        let id3 = ext == "mp3" ? parseId3v2(path) : nil // handles GBK/CJK tags AVFoundation mangles

        var title = await firstValue(meta, .commonKeyTitle)
        var artist = await firstValue(meta, .commonKeyArtist)
        var album = await firstValue(meta, .commonKeyAlbumName)
        var genre = await firstValue(meta, .commonKeyType)
        var yearStr = await firstValue(meta, .commonKeyCreationDate)

        var year = 0
        var trackNo = 0
        var discNo = 0

        // Manual tag blocks take precedence (deterministic decoding)
        if let vorbis {
            if let v = vorbis["title"] { title = v }
            if let v = vorbis["artist"] { artist = v }
            if let v = vorbis["album"] { album = v }
            if let v = vorbis["genre"] { genre = v }
            if let v = vorbis["date"] { yearStr = v }
        } else if let id3 {
            if let v = id3["title"] { title = v }
            if let v = id3["artist"] { artist = v }
            if let v = id3["album"] { album = v }
            if let v = id3["genre"] { genre = v }
            if let v = id3["year"] { yearStr = v }
            if let v = id3["track"] { trackNo = Int(v) ?? 0 }
            if let v = id3["disc"] { discNo = Int(v) ?? 0 }
        }

        // Did the FILE itself carry readable tags? This is what separates a
        // real embedded baseline ("file") from the filename-derived fallback
        // below — the renderer records it so an online fill-in can be told
        // apart from what the audio file says.
        let hasFileTags = (vorbis?.isEmpty == false) || (id3?.isEmpty == false)
            || title != nil || artist != nil || album != nil

        // Embedded lyrics. FLAC Vorbis comments and ID3 USLT/SYLT come from the
        // manual parsers (AVFoundation hides/mangles them); M4A ©lyr and any
        // ID3 lyrics AVFoundation does surface arrive through identifiers.
        var embeddedLyrics = readEmbeddedLyrics(atPath: path)
        if embeddedLyrics == nil, let allMeta = try? await asset.load(.metadata) {
            for it in allMeta {
                guard let ident = it.identifier,
                      ident == .iTunesMetadataLyrics || ident == .id3MetadataUnsynchronizedLyric
                else { continue }
                if let s = try? await it.load(.stringValue),
                   !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    embeddedLyrics = s
                    break
                }
            }
        }

        let baseName = (path as NSString).lastPathComponent
        if title == nil || title!.isEmpty {
            title = cleanAudioStem(((baseName as NSString).deletingPathExtension))
        }

        if let ys = yearStr, ys.count >= 4 {
            year = Int(ys.prefix(4)) ?? 0
        }

        // Track number: value is {trackNumber, totalTrackCount}
        for it in meta where it.commonKey == AVMetadataKey(rawValue: "tracknumber") {
            if let d = (try? await it.load(.value)) as? [String: Any] {
                if trackNo == 0, let n = d["trackNumber"] as? NSNumber { trackNo = Int(truncating: n) }
                if discNo == 0, let n = d["discNumber"] as? NSNumber { discNo = Int(truncating: n) }
            }
        }

        // Audio track -> sample rate / channels
        var sampleRate = 0.0
        var channels = 0
        for t in tracks where t.mediaType == .audio {
            if let fds = try? await t.load(.formatDescriptions), let fd = fds.first {
                let afd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)
                if let asbd = afd {
                    sampleRate = asbd.pointee.mSampleRate
                    channels = Int(asbd.pointee.mChannelsPerFrame)
                }
            }
            break
        }

        var durationSec = CMTimeGetSeconds(duration)
        if !durationSec.isFinite || durationSec <= 0 { durationSec = 0 }

        let fileSize = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.uint64Value ?? 0
        // Bitrate from size/duration (kbps), like "1411 kbps"
        var bitrateKbps = 0
        if durationSec > 1, fileSize > 0 {
            bitrateKbps = Int(Double(fileSize) * 8.0 / durationSec / 1000.0)
        }

        var out: [String: Any] = [
            "title": title ?? "",
            "artist": (artist?.isEmpty ?? true) ? "Unknown Artist" : artist!,
            "album": (album?.isEmpty ?? true) ? "Unknown Album" : album!,
            "track_number": trackNo != 0 ? NSNumber(value: trackNo) : NSNull(),
            "disc_number": discNo != 0 ? NSNumber(value: discNo) : NSNull(),
            "genre": (genre?.isEmpty ?? true) ? NSNull() : genre!,
            "year": year != 0 ? NSNumber(value: year) : NSNull(),
            "duration": NSNumber(value: durationSec),
            "file_name": baseName,
            "file_size": NSNumber(value: fileSize),
            "file_format": ext,
            "bitrate": bitrateKbps != 0 ? NSNumber(value: bitrateKbps) : NSNull(),
            "sample_rate": sampleRate != 0 ? NSNumber(value: sampleRate) : NSNull(),
            "channels": channels != 0 ? NSNumber(value: channels) : NSNull(),
            // Provenance of the baseline: where each value came from, so the
            // UI can say "from file" and an online fill-in is distinguishable.
            // Cover/lyrics sources are stamped by the writer (import pipeline /
            // reset flow) once the value is actually persisted.
            "meta_source": hasFileTags ? "file" : "filename",
            "cover_source": NSNull(),
            "lyrics": embeddedLyrics ?? NSNull(),
            "lyrics_source": embeddedLyrics != nil ? "file" : NSNull(),
        ]

        // Cover art. AVFoundation exposes APIC (MP3) and covr (M4A) but not a
        // FLAC PICTURE block — without the manual read, a tagged FLAC looked
        // like it had no artwork and an online backend "filled in" a cover the
        // file already carried.
        var artworkData: Data?
        for it in meta where it.commonKey == .commonKeyArtwork {
            if let artwork = (try? await it.load(.value)) as? Data, artwork.count > 0 {
                artworkData = artwork
            } else if let d = (try? await it.load(.value)) as? [String: Any], let artwork = d["data"] as? Data, artwork.count > 0 {
                artworkData = artwork
            }
            break
        }
        if artworkData == nil, ext == "flac" {
            artworkData = readEmbeddedCover(atPath: path)
        }
        if let artworkData {
            out["artwork"] = artworkData
            out["cover_source"] = "file"
        }
        return out
    }
}