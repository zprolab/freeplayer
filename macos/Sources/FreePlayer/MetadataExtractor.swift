import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

/// Extracted metadata for one audio file (mirrors the old shell/metadata.mm).
struct ExtractedMetadata {
    var title: String
    var artist: String
    var album: String
    var trackNumber: Int?
    var discNumber: Int?
    var genre: String?
    var year: Int?
    var duration: Double
    var fileName: String
    var fileSize: Int64
    var fileFormat: String?
    var bitrate: Int?
    var sampleRate: Double?
    var channels: Int?
    var artwork: Data?

    static let supportedExtensions: Set<String> = [
        "mp3", "flac", "wav", "ogg", "m4a", "aac", "wma", "opus", "aiff", "aif", "ape"
    ]

    static func isAudioFile(_ path: String) -> Bool {
        supportedExtensions.contains((path as NSString).pathExtension.lowercased())
    }
}

enum MetadataExtractor {

    // ── Sidecar .lrc detection ──

    /// Strip downloader suffixes: "Artist - Title_EM.flac" -> "Artist - Title"
    private static func cleanStem(_ stem: String) -> String {
        var out = stem
        if let r = out.range(of: "_[A-Za-z]{1,4}$", options: .regularExpression) {
            out.removeSubrange(r)
        }
        return out
    }

    static func findSidecarLrc(forAudioPath path: String) -> String? {
        let dir = (path as NSString).deletingLastPathComponent
        let audioStem = cleanStem(((path as NSString).lastPathComponent as NSString).deletingPathExtension)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []

        var candidates: [(stem: String, name: String)] = []
        for name in files {
            guard (name as NSString).pathExtension.lowercased() == "lrc" else { continue }
            let stem = cleanStem(((name as NSString).deletingPathExtension))
            if stem == audioStem {
                return dir + "/" + name
            }
            candidates.append((stem, name))
        }
        // Prefix match: "Welcome Home" is a prefix of "Welcome Home, Son (Remaster)"
        for cand in candidates {
            let a = audioStem.lowercased()
            let s = cand.stem.lowercased()
            let minLen = min(a.count, s.count)
            if minLen >= 8 && s.hasPrefix(a) {
                return dir + "/" + cand.name
            }
        }
        return nil
    }

    // ── FLAC VORBIS_COMMENT parser ──

    private static func parseFlacVorbisComments(path: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count >= 4,
              Array(data[0..<4]) == Array("fLaC".utf8) else { return nil }

        var tags: [String: String] = [:]
        var offset = 4
        while offset + 4 <= data.count {
            let blockHeader = data[offset]
            let type = Int(blockHeader & 0x7f)
            let len = Int(data[offset+1]) << 16 | Int(data[offset+2]) << 8 | Int(data[offset+3])
            offset += 4
            guard offset + len <= data.count else { return tags.isEmpty ? nil : tags }

            if type == 4 { // VORBIS_COMMENT
                var p = offset
                let end = offset + len

                func readUInt32() -> UInt32? {
                    guard p + 4 <= end else { return nil }
                    let v = UInt32(data[p]) | (UInt32(data[p+1]) << 8) | (UInt32(data[p+2]) << 16) | (UInt32(data[p+3]) << 24)
                    p += 4
                    return v
                }

                guard let vendorLen = readUInt32(), p + Int(vendorLen) <= end else { return nil }
                p += Int(vendorLen)
                guard let count = readUInt32() else { return nil }

                for _ in 0..<count {
                    guard let clen = readUInt32(), p + Int(clen) <= end else { break }
                    let entryData = data.subdata(in: p..<(p + Int(clen)))
                    p += Int(clen)
                    guard let entry = String(data: entryData, encoding: .utf8),
                          let eq = entry.firstIndex(of: "=") else { continue }
                    let key = String(entry[..<eq]).lowercased()
                    let value = String(entry[entry.index(after: eq)...])
                    if !key.isEmpty && !value.isEmpty {
                        tags[key] = value
                    }
                }
                return tags.isEmpty ? nil : tags
            }
            offset += len
        }
        return tags.isEmpty ? nil : tags
    }

    // ── ID3v2 parser ──

    /// Decode an ID3v2 text frame. Encoding byte: 0=ISO-8859-1 (often GBK for
    /// CJK), 1=UTF-16 w/ BOM, 2=UTF-16BE, 3=UTF-8.
    private static func decodeId3Text(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        let enc = bytes[0]
        var text = Array(bytes.dropFirst())
        if enc == 0 {
            // Heuristic: mostly high bytes → likely GBK mislabeled as Latin-1
            var high = 0
            for b in text where b > 0x7F { high += 1 }
            if !text.isEmpty && high * 10 > text.count * 3 {
                let gbEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
                if let s = String(bytes: text, encoding: gbEncoding), !s.contains("\u{FFFD}") {
                    return s
                }
            }
            return String(bytes: text, encoding: .isoLatin1) ?? ""
        }
        if enc == 1 {
            if text.count >= 2 && text[text.count - 1] == 0 && text[text.count - 2] == 0 {
                text.removeLast(2)
            }
            return String(bytes: text, encoding: .utf16) ?? ""
        }
        if enc == 2 {
            return String(bytes: text, encoding: .utf16BigEndian) ?? ""
        }
        return String(bytes: text, encoding: .utf8) ?? ""
    }

    private static func parseId3v2(path: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count >= 10,
              Array(data[0..<3]) == Array("ID3".utf8) else { return nil }

        let bytes = [UInt8](data)
        let ver = bytes[3]
        guard ver == 3 || ver == 4 else { return nil }
        let tagSize = Int(bytes[6] & 0x7f) << 21 | Int(bytes[7] & 0x7f) << 14 | Int(bytes[8] & 0x7f) << 7 | Int(bytes[9] & 0x7f)
        let maxSize = min(tagSize, data.count - 10)
        var p = 10
        let end = 10 + maxSize

        if p < end && (bytes[p + 5] & 0x40) != 0 { // extended header
            var extSize = 0
            if ver == 4 {
                // v2.4: size (synchsafe) excludes the 4 size bytes themselves
                extSize = Int(bytes[p+6] & 0x7f) << 21 | Int(bytes[p+7] & 0x7f) << 14 | Int(bytes[p+8] & 0x7f) << 7 | Int(bytes[p+9] & 0x7f)
                p += 10 + 4 + extSize
            } else {
                // v2.3: size includes the 4 size bytes
                extSize = Int(bytes[p+6]) << 24 | Int(bytes[p+7]) << 16 | Int(bytes[p+8]) << 8 | Int(bytes[p+9])
                p += 10 + extSize
            }
        }

        var tags: [String: String] = [:]
        while p + 10 <= end {
            let idChars = Array(bytes[p..<(p+4)])
            let id = String(bytes: idChars, encoding: .ascii) ?? ""
            var size = 0
            if ver == 4 {
                size = Int(bytes[p+4] & 0x7f) << 21 | Int(bytes[p+5] & 0x7f) << 14 | Int(bytes[p+6] & 0x7f) << 7 | Int(bytes[p+7] & 0x7f)
            } else {
                size = Int(bytes[p+4]) << 24 | Int(bytes[p+5]) << 16 | Int(bytes[p+6]) << 8 | Int(bytes[p+7])
            }
            let frame = p + 10
            guard frame + size <= end else { break }
            if size > 0 && id.hasPrefix("T") {
                let value = decodeId3Text(Array(bytes[frame..<(frame + size)]))
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
            p = frame + size
        }
        return tags.isEmpty ? nil : tags
    }

    // ── Main extraction ──

    private static func firstValue(_ items: [AVMetadataItem], _ key: String) -> String? {
        for item in items where item.commonKey?.rawValue == key {
            if let value = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Extract everything the import pipeline needs. Synchronous; call on a
    /// background queue. Returns nil on failure.
    static func extract(atPath path: String) -> ExtractedMetadata? {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url, options: nil)

        let semaphore = DispatchSemaphore(value: 0)
        var loaded = false
        asset.loadValuesAsynchronously(forKeys: ["commonMetadata", "duration", "tracks"]) {
            loaded = true
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        guard loaded else { return nil }

        let meta = asset.commonMetadata
        var out = ExtractedMetadata(title: "", artist: Track.unknownArtist, album: Track.unknownAlbum,
                                    trackNumber: nil, discNumber: nil, genre: nil, year: nil,
                                    duration: 0, fileName: (path as NSString).lastPathComponent,
                                    fileSize: 0, fileFormat: nil, bitrate: nil,
                                    sampleRate: nil, channels: nil, artwork: nil)

        let ext = (path as NSString).pathExtension.lowercased()
        let vorbis = ext == "flac" ? parseFlacVorbisComments(path: path) : nil
        let id3 = ext == "mp3" ? parseId3v2(path: path) : nil

        var title = firstValue(meta, AVMetadataKey.commonKeyTitle.rawValue)
        var artist = firstValue(meta, AVMetadataKey.commonKeyArtist.rawValue)
        var album = firstValue(meta, AVMetadataKey.commonKeyAlbumName.rawValue)
        var genre = firstValue(meta, AVMetadataKey.commonKeyType.rawValue)
        var yearStr = firstValue(meta, AVMetadataKey.commonKeyCreationDate.rawValue)

        var trackNo = 0
        var discNo = 0

        // Manual tag blocks take precedence (deterministic decoding)
        if let vorbis {
            title = vorbis["title"] ?? title
            artist = vorbis["artist"] ?? artist
            album = vorbis["album"] ?? album
            genre = vorbis["genre"] ?? genre
            yearStr = vorbis["date"] ?? yearStr
        } else if let id3 {
            title = id3["title"] ?? title
            artist = id3["artist"] ?? artist
            album = id3["album"] ?? album
            genre = id3["genre"] ?? genre
            yearStr = id3["year"] ?? yearStr
            if let t = id3["track"] { trackNo = Int(t) ?? 0 }
            if let d = id3["disc"] { discNo = Int(d) ?? 0 }
        }

        if title == nil || title!.isEmpty {
            let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            title = cleanStem(stem)
        }

        if let yearStr, yearStr.count >= 4 {
            out.year = Int(yearStr.prefix(4))
        }

        // Track number from AVFoundation dictionary form
        if trackNo == 0 {
            for item in meta where item.commonKey?.rawValue == "tracknumber" {
                if let d = item.value as? [String: Any] {
                    if trackNo == 0 { trackNo = (d["trackNumber"] as? NSNumber)?.intValue ?? 0 }
                    if discNo == 0 { discNo = (d["discNumber"] as? NSNumber)?.intValue ?? 0 }
                }
            }
        }

        // Sample rate / channels
        var sampleRate: Double = 0
        var channels = 0
        for t in asset.tracks where t.mediaType == .audio {
            // Audio track format descriptions are always CMAudioFormatDescription;
            // CF types can't be conditional-cast in Swift.
            if let fd = t.formatDescriptions.first as! CMAudioFormatDescription? {
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd) {
                    sampleRate = asbd.pointee.mSampleRate
                    channels = Int(asbd.pointee.mChannelsPerFrame)
                }
            }
            break
        }

        let duration = CMTimeGetSeconds(asset.duration)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        var bitrateKbps = 0
        if duration > 1 && fileSize > 0 {
            bitrateKbps = Int(Double(fileSize) * 8.0 / duration / 1000.0)
        }

        out.title = title ?? ""
        out.artist = (artist?.isEmpty ?? true) ? Track.unknownArtist : artist!
        out.album = (album?.isEmpty ?? true) ? Track.unknownAlbum : album!
        out.trackNumber = trackNo > 0 ? trackNo : nil
        out.discNumber = discNo > 0 ? discNo : nil
        out.genre = (genre?.isEmpty ?? true) ? nil : genre
        out.duration = duration.isFinite && duration > 0 ? duration : 0
        out.fileSize = fileSize
        out.fileFormat = ext
        out.bitrate = bitrateKbps > 0 ? bitrateKbps : nil
        out.sampleRate = sampleRate > 0 ? sampleRate : nil
        out.channels = channels > 0 ? channels : nil

        // Cover art
        for item in meta where item.commonKey?.rawValue == AVMetadataKey.commonKeyArtwork.rawValue {
            if let data = item.value as? Data {
                out.artwork = data
                break
            } else if let d = item.value as? [String: Any], let data = d["data"] as? Data {
                out.artwork = data
                break
            }
        }

        return out
    }
}
