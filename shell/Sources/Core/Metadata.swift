// FreePlayer shell — audio metadata extraction via AVFoundation
// Replaces music-metadata (electron). Synchronous (semaphore) so the
// import loop stays simple; call from a background queue.

import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

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

    // Parse FLAC VORBIS_COMMENT block manually (AVFoundation hides these tags).
    // Returns nil if the file isn't a FLAC / has no comments.
    private static func parseFlacVorbisComments(_ path: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count >= 4, Array(data.prefix(4)) == [0x66, 0x4C, 0x61, 0x43] /* "fLaC" */ else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [String: String]? in
            guard let base = raw.baseAddress else { return nil }
            var p = base.assumingMemoryBound(to: UInt8.self) + 4
            var remaining = data.count - 4
            while remaining >= 4 {
                let blockHeader = p[0]
                let type = Int(blockHeader & 0x7f)
                let len = (UInt32(p[1]) << 16) | (UInt32(p[2]) << 8) | UInt32(p[3])
                p += 4; remaining -= 4
                if remaining < Int(len) { return nil }
                if type == 4 { // VORBIS_COMMENT
                    var c = p
                    var cRem = Int(len)
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
                    for _ in 0..<count where cRem >= 4 {
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
                p += Int(len); remaining -= Int(len)
            }
            return nil
        }
    }

    // Decode an ID3v2 text frame. Encoding byte: 0=ISO-8859-1 (often actually
    // GBK for CJK tags), 1=UTF-16 w/ BOM, 2=UTF-16BE, 3=UTF-8.
    private static func decodeId3Text(_ p: UnsafePointer<UInt8>, _ len: UInt32) -> String {
        if len == 0 { return "" }
        let enc = p[0]
        let text = p + 1
        var textLen = Int(len) - 1
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
                if size > 0, id.hasPrefix("T") {
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
                p = frame + Int(size)
            }
            return tags.isEmpty ? nil : tags
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
        var result: [String: Any]?
        Task.detached {
            result = await Self.extractAsync(asset: asset, path: path)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 10)
        return result
    }

    private static func extractAsync(asset: AVURLAsset, path: String) async -> [String: Any]? {
        // M10: a load failure is the only failure signal — on timeout or error
        // the caller falls back to filename-derived tags.
        guard let (meta, duration, tracks) = try? await asset.load(.commonMetadata, .duration, .tracks) else {
            return nil
        }

        // FLAC: pull Vorbis comments manually (AVFoundation hides them)
        let ext = (path as NSString).pathExtension.lowercased()
        let vorbis = ext == "flac" ? parseFlacVorbisComments(path) : nil
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
        ]

        // Cover art
        for it in meta where it.commonKey == .commonKeyArtwork {
            if let artwork = (try? await it.load(.value)) as? Data, artwork.count > 0 {
                out["artwork"] = artwork
            } else if let d = (try? await it.load(.value)) as? [String: Any], let artwork = d["data"] as? Data, artwork.count > 0 {
                out["artwork"] = artwork
            }
            break
        }
        return out
    }
}