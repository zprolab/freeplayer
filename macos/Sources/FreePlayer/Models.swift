import Foundation

// ── App-level enums ──

enum AppView: String, CaseIterable {
    case library, nowPlaying, stats, settings
}

enum ImportMode: String, CaseIterable {
    case copy, symlink
}

enum VisualizerMode: String, CaseIterable {
    case waveform, spectrogram, off
}

enum PlayMode: String, CaseIterable {
    case sequential, repeatOne, shuffle
}

// ── Core entities ──

struct Track: Identifiable, Equatable, Hashable {
    var id: Int64
    var title: String
    var artist: String
    var album: String
    var trackNumber: Int?
    var discNumber: Int?
    var genre: String?
    var year: Int?
    var duration: Double
    var filePath: String
    var fileName: String
    var fileSize: Int64
    var fileFormat: String?
    var bitrate: Int?
    var sampleRate: Double?
    var channels: Int?
    var coverPath: String?
    var replaygainGain: Double
    var replaygainPeak: Double
    var lrcPath: String?
    var playCount: Int64
    var lastPlayedAt: Date?
    var importedAt: Date?
    var updatedAt: Date?

    static let unknownArtist = "Unknown Artist"
    static let unknownAlbum = "Unknown Album"
}

struct Playlist: Identifiable, Equatable, Hashable {
    var id: Int64
    var name: String
    var description: String?
    var createdAt: Date?
    var updatedAt: Date?
}

struct PlayHistoryEntry: Identifiable, Equatable {
    var id: Int64
    var trackId: Int64
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Double
    var playPercentage: Double
    var title: String
    var artist: String
    var album: String
    var filePath: String
    var trackDuration: Double
}

struct TopTrack: Identifiable, Equatable {
    var id: Int64
    var title: String
    var artist: String
    var album: String
    var trackDuration: Double
    var playCount: Int64
    var totalListenTime: Double
}

struct TopArtist: Identifiable, Equatable {
    var id: String { artist }
    var artist: String
    var playCount: Int64
    var totalListenTime: Double
}

struct DailyStat: Identifiable, Equatable {
    var id: String { date }
    var date: String
    var plays: Int64
    var totalTime: Double
}

struct ListeningStats: Equatable {
    var totalTime: Double
    var totalPlays: Int64
    var uniqueTracksPlayed: Int64
    var topTracks: [TopTrack]
    var topArtists: [TopArtist]
    var dailyStats: [DailyStat]
}

// ── Formatting helpers (shared by views) ──

enum Formatting {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    static func tableDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--:--" }
        return time(seconds)
    }

    static func statsDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0m" }
        let h = Int(seconds) / 3600
        let m = Int(seconds) % 3600 / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func fileSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var size = Double(bytes)
        var idx = 0
        while size >= 1024 && idx < units.count - 1 {
            size /= 1024
            idx += 1
        }
        if idx == 0 { return "\(Int(size)) \(units[idx])" }
        return String(format: "%.1f %@", size, units[idx])
    }

    static func number(_ n: Int64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func compactDate(_ date: Date?) -> String {
        guard let date else { return "--" }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
