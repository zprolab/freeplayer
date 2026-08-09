import SwiftUI

struct StatsView: View {
    @State private var stats: ListeningStats?
    @State private var history: [PlayHistoryEntry] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Loading statistics...").foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let stats {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        cards(stats)
                        HStack(alignment: .top, spacing: 16) {
                            topTracksPanel(stats)
                            topArtistsPanel(stats)
                        }
                        if !stats.dailyStats.isEmpty {
                            dailyChart(stats)
                        }
                        recentPlaysPanel
                    }
                    .frame(maxWidth: 1100)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Theme.background)
        .onAppear(perform: load)
    }

    private func load() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let s = Database.shared.listeningStats()
            let h = Database.shared.playHistory(limit: 30)
            DispatchQueue.main.async {
                self.stats = s
                self.history = h
                self.loading = false
            }
        }
    }

    // ── Cards ──

    private func cards(_ stats: ListeningStats) -> some View {
        HStack(spacing: 16) {
            statCard(icon: "clock", color: .orange, value: Formatting.statsDuration(stats.totalTime), label: "Total Listening Time")
            statCard(icon: "play.fill", color: .blue, value: Formatting.number(stats.totalPlays), label: "Total Plays")
            statCard(icon: "music.note", color: .green, value: Formatting.number(stats.uniqueTracksPlayed), label: "Unique Tracks")
        }
    }

    private func statCard(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border.opacity(0.5)))
    }

    // ── Panels ──

    private func topTracksPanel(_ stats: ListeningStats) -> some View {
        PanelBox {
            VStack(alignment: .leading, spacing: 0) {
                panelTitle("Most Played Tracks")
                if stats.topTracks.isEmpty {
                    Text("No play data yet.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                        .padding(20)
                } else {
                    tableHeader(["#", "Title", "Artist", "Plays", "Time"],
                                columnWidths: [24, 1, 1, 56, 56],
                                alignments: [.leading, .leading, .leading, .trailing, .trailing])
                    ForEach(Array(stats.topTracks.enumerated()), id: \.element.id) { idx, t in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 24, alignment: .leading)
                            Text(t.title).lineLimit(1).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(t.artist).lineLimit(1).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Formatting.number(t.playCount))
                                .font(Theme.mono).foregroundStyle(Theme.textSecondary)
                                .frame(width: 56, alignment: .trailing)
                            Text(Formatting.statsDuration(t.totalListenTime))
                                .font(Theme.mono).foregroundStyle(Theme.textTertiary)
                                .frame(width: 56, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func topArtistsPanel(_ stats: ListeningStats) -> some View {
        PanelBox {
            VStack(alignment: .leading, spacing: 0) {
                panelTitle("Top Artists")
                if stats.topArtists.isEmpty {
                    Text("No play data yet.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                        .padding(20)
                } else {
                    tableHeader(["#", "Artist", "Plays", "Time"],
                                columnWidths: [24, 1, 56, 56],
                                alignments: [.leading, .leading, .trailing, .trailing])
                    ForEach(Array(stats.topArtists.enumerated()), id: \.element.id) { idx, a in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 24, alignment: .leading)
                            Text(a.artist)
                                .lineLimit(1)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Formatting.number(a.playCount))
                                .font(Theme.mono).foregroundStyle(Theme.textSecondary)
                                .frame(width: 56, alignment: .trailing)
                            Text(Formatting.statsDuration(a.totalListenTime))
                                .font(Theme.mono).foregroundStyle(Theme.textTertiary)
                                .frame(width: 56, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // M3: panel title bar (13px semibold + bottom border)
    private func panelTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
    }

    private func tableHeader(_ labels: [String], columnWidths: [CGFloat], alignments: [Alignment]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: columnWidths[idx] == 1 ? .infinity : columnWidths[idx],
                           alignment: alignments[idx])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
    }

    // ── Daily chart (14 bars) ──

    private func dailyChart(_ stats: ListeningStats) -> some View {
        PanelBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Listening History (30 days)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                let maxTime = max(stats.dailyStats.map(\.totalTime).max() ?? 1, 1)
                let days = Array(stats.dailyStats.prefix(14).reversed())
                HStack(alignment: .bottom, spacing: 6) {
                    Spacer(minLength: 0)
                    ForEach(days, id: \.date) { day in
                        VStack(spacing: 4) {
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.blue)
                                    .frame(height: max(CGFloat(day.totalTime / maxTime) * geo.size.height, 2))
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                            Text(shortDate(day.date))
                                .font(Theme.mono)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(width: 22)
                        .help("\(Formatting.statsDuration(day.totalTime)) - \(day.plays) plays")
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 160)
            }
        }
    }

    private func shortDate(_ date: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return date }
        return d.formatted(.dateTime.month().day())
    }

    // ── Recent plays ──

    private var recentPlaysPanel: some View {
        PanelBox {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent Plays")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 12)
                if history.isEmpty {
                    Text("No play history yet.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                } else {
                    recentHeader
                    Divider()
                    ForEach(history) { entry in
                        recentRow(entry)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
    }

    private var recentHeader: some View {
        HStack(spacing: 16) {
            header("TITLE").frame(maxWidth: .infinity, alignment: .leading)
            header("ARTIST").frame(maxWidth: .infinity, alignment: .leading)
            header("STARTED").frame(maxWidth: .infinity, alignment: .leading)
            header("DURATION").frame(width: 100, alignment: .trailing)
            header("%").frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }

    private func recentRow(_ entry: PlayHistoryEntry) -> some View {
        HStack(spacing: 16) {
            Text(entry.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.artist).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(Formatting.statsStarted(entry.startedAt)).frame(maxWidth: .infinity, alignment: .leading)
            Text(Formatting.statsDuration(entry.durationSeconds)).frame(width: 100, alignment: .trailing)
            Text("\(Int(entry.playPercentage))%").frame(width: 48, alignment: .trailing)
        }
        .font(Theme.mono)
        .foregroundStyle(Theme.textSecondary)
        .padding(.vertical, 3)
    }
}
