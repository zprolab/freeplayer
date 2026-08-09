import Foundation

/// Fetches missing synchronized lyrics from LRCLIB and artwork from iTunes.
/// Requests are paced because both public endpoints throttle burst traffic.
actor MetadataFetchService {
    static let shared = MetadataFetchService()

    struct Candidate: Equatable {
        let title: String
        let artist: String
    }

    private struct LrclibItem: Decodable {
        let trackName: String?
        let artistName: String?
        let syncedLyrics: String?

        private enum CodingKeys: String, CodingKey {
            case trackName, artistName, syncedLyrics
            case snakeTrackName = "track_name"
            case snakeArtistName = "artist_name"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            trackName = try values.decodeIfPresent(String.self, forKey: .trackName)
                ?? values.decodeIfPresent(String.self, forKey: .snakeTrackName)
            artistName = try values.decodeIfPresent(String.self, forKey: .artistName)
                ?? values.decodeIfPresent(String.self, forKey: .snakeArtistName)
            syncedLyrics = try values.decodeIfPresent(String.self, forKey: .syncedLyrics)
        }
    }

    private struct ITunesResponse: Decodable {
        let results: [ITunesItem]
    }

    private struct ITunesItem: Decodable {
        let trackName: String?
        let artistName: String?
        let artworkUrl100: String?
    }

    private enum Endpoint { case lrclib, itunes }

    private let session: URLSession
    private let lrclibMinInterval: TimeInterval
    private let itunesMinInterval: TimeInterval
    private var lastLrclibRequest = Date.distantPast
    private var lastITunesRequest = Date.distantPast
    private var lrclibCooldownUntil = Date.distantPast
    private var itunesCooldownUntil = Date.distantPast

    init(
        session: URLSession = .shared,
        lrclibMinInterval: TimeInterval = 1.2,
        itunesMinInterval: TimeInterval = 3.0
    ) {
        self.session = session
        self.lrclibMinInterval = lrclibMinInterval
        self.itunesMinInterval = itunesMinInterval
    }

    func fetchLyrics(for track: Track) async -> String? {
        guard Date() >= lrclibCooldownUntil else { return nil }
        let artistKnown = !track.artist.isEmpty && track.artist != Track.unknownArtist

        if artistKnown, let url = Self.lrclibGetURL(for: track) {
            await pace(.lrclib)
            if let result = await jsonData(from: url, endpoint: .lrclib),
               let item = try? JSONDecoder().decode(LrclibItem.self, from: result),
               let lyrics = Self.nonempty(item.syncedLyrics) {
                return lyrics
            }
        }

        guard let searchURL = Self.lrclibSearchURL(for: track) else { return nil }
        await pace(.lrclib)
        guard let data = await jsonData(from: searchURL, endpoint: .lrclib),
              let items = try? JSONDecoder().decode([LrclibItem].self, from: data) else { return nil }
        let candidates = items.map { Candidate(title: $0.trackName ?? "", artist: $0.artistName ?? "") }
        guard let index = Self.bestMatchIndex(in: candidates, for: track),
              items.indices.contains(index) else { return nil }
        return Self.nonempty(items[index].syncedLyrics)
    }

    func fetchCover(for track: Track) async -> Data? {
        guard Date() >= itunesCooldownUntil,
              let url = Self.itunesSearchURL(for: track) else { return nil }
        await pace(.itunes)

        var data = await jsonData(from: url, endpoint: .itunes)
        if data == nil {
            try? await Task.sleep(nanoseconds: 500_000_000)
            data = await jsonData(from: url, endpoint: .itunes)
        }
        guard let data,
              let response = try? JSONDecoder().decode(ITunesResponse.self, from: data) else { return nil }
        let candidates = response.results.map { Candidate(title: $0.trackName ?? "", artist: $0.artistName ?? "") }
        guard let index = Self.bestMatchIndex(in: candidates, for: track),
              response.results.indices.contains(index),
              let artwork = response.results[index].artworkUrl100,
              let artworkURL = URL(string: Self.largeArtworkURL(artwork)) else { return nil }
        return await binaryData(from: artworkURL)
    }

    private func pace(_ endpoint: Endpoint) async {
        let last = endpoint == .lrclib ? lastLrclibRequest : lastITunesRequest
        let interval = endpoint == .lrclib ? lrclibMinInterval : itunesMinInterval
        let wait = interval - Date().timeIntervalSince(last)
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        if endpoint == .lrclib { lastLrclibRequest = Date() }
        else { lastITunesRequest = Date() }
    }

    private func jsonData(from url: URL, endpoint: Endpoint) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("FreePlayer/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 429 || (endpoint == .itunes && http.statusCode == 403) {
                let seconds = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 5
                if endpoint == .lrclib { lrclibCooldownUntil = Date().addingTimeInterval(seconds) }
                else { itunesCooldownUntil = Date().addingTimeInterval(seconds) }
                return nil
            }
            guard (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func binaryData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
            return data
        } catch {
            return nil
        }
    }

    static func normalizeForMatch(_ value: String) -> String {
        String(value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = normalizeForMatch(lhs)
        let b = normalizeForMatch(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        if a.contains(b) || b.contains(a) { return 0.9 }
        let left = a.split(separator: " ")
        let right = b.split(separator: " ")
        let common = left.filter { right.contains($0) }.count
        return Double(common) / Double(max(left.count, right.count))
    }

    static func bestMatchIndex(in candidates: [Candidate], for track: Track) -> Int? {
        let unknownArtist = track.artist.isEmpty || track.artist == Track.unknownArtist
        var bestIndex: Int?
        var bestScore = 0.0
        for (index, candidate) in candidates.enumerated() {
            let titleScore = similarity(candidate.title, track.title)
            guard titleScore >= 0.8 else { continue }
            let artistScore = unknownArtist ? 1 : similarity(candidate.artist, track.artist)
            guard unknownArtist || artistScore >= 0.5 else { continue }
            let score = titleScore * 0.7 + artistScore * 0.3
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestIndex
    }

    static func lrclibGetURL(for track: Track) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items: [URLQueryItem] = []
        if !track.artist.isEmpty && track.artist != Track.unknownArtist {
            items.append(URLQueryItem(name: "artist_name", value: track.artist))
        }
        if !track.title.isEmpty { items.append(URLQueryItem(name: "track_name", value: track.title)) }
        if !track.album.isEmpty && track.album != Track.unknownAlbum {
            items.append(URLQueryItem(name: "album_name", value: track.album))
        }
        if track.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))))
        }
        components?.queryItems = items
        return components?.url
    }

    static func lrclibSearchURL(for track: Track) -> URL? {
        let query = [track.title, track.artist == Track.unknownArtist ? "" : track.artist]
            .filter { !$0.isEmpty }.joined(separator: " ")
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    static func itunesSearchURL(for track: Track) -> URL? {
        let term = [track.title, track.artist == Track.unknownArtist ? "" : track.artist]
            .filter { !$0.isEmpty }.joined(separator: " ")
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        return components?.url
    }

    static func largeArtworkURL(_ value: String) -> String {
        value.replacingOccurrences(of: #"\d+x\d+"#, with: "600x600", options: .regularExpression)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
