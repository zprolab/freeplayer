import Foundation
import ChromaSwift

/// Content-based audio identification (fingerprint → AcoustID → metadata).
///
/// Works regardless of file names: a random-named download is recognized by
/// its audio content, then the real title/artist are written back, and cover
/// art (iTunes) + synced lyrics (LRCLIB) are fetched via MetadataFetchService.
///
/// A recognition confidence gate (minimumScore) protects against wrong
/// matches — e.g. two different songs sharing the same title. If the
/// fingerprint match is unreliable the whole pipeline is aborted.
struct AudioRecognizer {

    static let defaultAPIKey = "j63lxXduqF"

    /// Below this AcoustID score the match is considered unreliable
    /// (possible same-title-different-song) and nothing is written back.
    static let minimumScore: Double = 0.8

    static var apiKey: String {
        let stored = UserDefaults.standard.string(forKey: "acoustid_api_key") ?? ""
        return stored.isEmpty ? defaultAPIKey : stored
    }

    /// Recognized track metadata from a local audio file (or nil).
    static func recognize(url: URL) async -> RecognizedTrack? {
        guard !apiKey.isEmpty else { return nil }

        // 1) Fingerprint from content (Chromaprint / AcoustID algorithm).
        let fingerprint: AudioFingerprint
        do {
            fingerprint = try AudioFingerprint(from: url)
        } catch {
            NSLog("[recognize] fingerprint failed: %@", error.localizedDescription)
            return nil
        }

        // 2) Online lookup. We query AcoustID directly instead of using the
        //    library client: its Codable parser is too strict for some real
        //    API responses (parseFail on perfectly valid replies).
        var components = URLComponents(string: "https://api.acoustid.org/v2/lookup")
        components?.queryItems = [
            URLQueryItem(name: "client", value: apiKey),
            URLQueryItem(name: "fingerprint", value: fingerprint.base64),
            URLQueryItem(name: "duration", value: String(Int(fingerprint.duration))),
            URLQueryItem(name: "meta", value: "recordings"),
        ]
        guard let requestURL = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: requestURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            // Lenient decoding: every field optional so odd API payloads
            // (extra artists, missing releasegroups…) never fail the lookup.
            let decoded = try JSONDecoder().decode(AcoustIDResponse.self, from: data)
            guard let result = decoded.results?.first,
                  let recording = result.recordings?.first,
                  let title = recording.title, !title.isEmpty else { return nil }
            let artist = recording.artists?.first?.name ?? ""
            return RecognizedTrack(title: title, artist: artist, score: result.score)
        } catch {
            NSLog("[recognize] acoustid lookup failed: %@", error.localizedDescription)
        }
        return nil
    }

    /// End-to-end auto-match for a random-named file:
    ///   fingerprint → recognize → (score gate) → update name → cover → lyrics
    /// Returns a summary of what was written (or nil when rejected/failed).
    struct MatchResult {
        let title: String
        let artist: String
        let score: Double
        let coverPath: String?
        let lrcPath: String?
    }

    /// Deduplicates concurrent auto-match attempts per file (multiple code
    /// paths — lyric fallback, backfill, auto-fetch — may race on one track).
    private actor MatchGate {
        private var inFlight: Set<String> = []
        func begin(_ path: String) -> Bool {
            guard !inFlight.contains(path) else { return false }
            inFlight.insert(path)
            return true
        }
        func end(_ path: String) {
            inFlight.remove(path)
        }
    }
    private static let gate = MatchGate()

    static func autoMatch(track: Track) async -> MatchResult? {
        guard await gate.begin(track.filePath) else { return nil }
        let result = await performMatch(track: track)
        await gate.end(track.filePath)
        return result
    }

    private static func performMatch(track: Track) async -> MatchResult? {
        let url = URL(fileURLWithPath: track.filePath)

        // 1) Recognize by content.
        guard let recognized = await recognize(url: url) else { return nil }

        // 2) Confidence gate — unreliable match (same-title-different-song,
        //    sparse fingerprint database) aborts the whole pipeline.
        guard recognized.score >= minimumScore else {
            NSLog("[match] score %.2f < %.2f, rejecting (possible name collision)",
                  recognized.score, minimumScore)
            return nil
        }

        // 3) Rebuild the track with the recognized identity so lyric/cover
        //    lookups use the true title/artist (never the file name).
        let identified = Track(
            id: track.id, title: recognized.title, artist: recognized.artist,
            album: track.album, trackNumber: track.trackNumber, discNumber: track.discNumber,
            genre: track.genre, year: track.year, duration: track.duration,
            filePath: track.filePath, fileName: track.fileName, fileSize: track.fileSize,
            fileFormat: track.fileFormat, bitrate: track.bitrate, sampleRate: track.sampleRate,
            channels: track.channels, coverPath: track.coverPath,
            replaygainGain: track.replaygainGain, replaygainPeak: track.replaygainPeak,
            lrcPath: track.lrcPath, playCount: track.playCount, lastPlayedAt: track.lastPlayedAt,
            importedAt: track.importedAt, updatedAt: track.updatedAt
        )

        // 4) Lyrics + cover (MetadataFetchService — LRCLIB / iTunes).
        async let lyrics = MetadataFetchService.shared.fetchLyrics(for: identified)
        async let coverData = MetadataFetchService.shared.fetchCover(for: identified)
        let (lyricsText, artwork) = await (lyrics, coverData)

        var coverPath: String? = nil
        if let artwork {
            coverPath = writeCover(artwork, for: url)
        }

        var lrcPath: String? = nil
        if let lyricsText {
            lrcPath = writeLrc(lyricsText, for: url)
        }

        return MatchResult(
            title: recognized.title,
            artist: recognized.artist,
            score: recognized.score,
            coverPath: coverPath,
            lrcPath: lrcPath
        )
    }

    // ── file writers ──

    static func writeLrc(_ lyrics: String, for url: URL) -> String? {
        let base = url.deletingPathExtension().lastPathComponent
        let lrcURL = url.deletingLastPathComponent().appendingPathComponent("\(base).lrc")
        do {
            try lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
            return lrcURL.path
        } catch {
            NSLog("[lyrics] write failed: %@", error.localizedDescription)
        }
        return nil
    }

    static func writeCover(_ data: Data, for url: URL) -> String? {
        // Matches the import pipeline: <album dir>/.covers/cover.jpg
        let dir = (url.path as NSString).deletingLastPathComponent
        let coverDir = dir + "/.covers"
        try? FileManager.default.createDirectory(atPath: coverDir, withIntermediateDirectories: true)
        let cover = coverDir + "/cover.jpg"
        do {
            try data.write(to: URL(fileURLWithPath: cover), options: .atomic)
            return cover
        } catch {
            NSLog("[cover] write failed: %@", error.localizedDescription)
        }
        return nil
    }
}

/// Result of an online recognition.
struct RecognizedTrack {
    let title: String
    let artist: String
    let score: Double
}

/// Lenient AcoustID lookup response (all fields optional).
private struct AcoustIDResponse: Decodable {
    struct Result: Decodable {
        let id: String?
        let score: Double
        let recordings: [Recording]?
    }
    struct Recording: Decodable {
        let title: String?
        let artists: [Artist]?
    }
    struct Artist: Decodable {
        let name: String?
    }
    let results: [Result]?
}
