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
                    .padding(16)
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
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border.opacity(0.5)))
    }

    // ── Panels ──

    private func topTracksPanel(_ stats: ListeningStats) -> some View {
        PanelBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Most Played Tracks")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if stats.topTracks.isEmpty {
                    Text("No play data yet.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(Array(stats.topTracks.enumerated()), id: \.element.id) { idx, t in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 20, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title).lineLimit(1).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                                Text(t.artist).lineLimit(1).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(Formatting.number(t.playCount))
                                    .font(Theme.mono).foregroundStyle(Theme.textSecondary)
                                Text(Formatting.statsDuration(t.totalListenTime))
                                    .font(Theme.mono).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func topArtistsPanel(_ stats: ListeningStats) -> some View {
        PanelBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Top Artists")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if stats.topArtists.isEmpty {
                    Text("No play data yet.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(Array(stats.topArtists.enumerated()), id: \.element.id) { idx, a in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 20, alignment: .leading)
                            Text(a.artist)
                                .lineLimit(1)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(Formatting.number(a.playCount))
                                    .font(Theme.mono).foregroundStyle(Theme.textSecondary)
                                Text(Formatting.statsDuration(a.totalListenTime))
                                    .font(Theme.mono).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
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
                        .help("\(Formatting.statsDuration(day.totalTime)) - \(day.plays) plays")
                    }
                }
                .frame(height: 120)
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Plays")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if history.isEmpty {
                    Text("No play history yet.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 16) {
                        GridRow {
                            header("Title"); header("Artist"); header("Started"); header("Duration").gridColumnAlignment(.trailing); header("%").gridColumnAlignment(.trailing)
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(history) { entry in
                            GridRow {
                                Text(entry.title).lineLimit(1).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                                Text(entry.artist).lineLimit(1).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(Theme.mono).foregroundStyle(Theme.textSecondary)
                                Text(Formatting.statsDuration(entry.durationSeconds))
                                    .font(Theme.mono).foregroundStyle(Theme.textSecondary)
                                    .gridColumnAlignment(.trailing)
                                Text("\(Int(entry.playPercentage))%")
                                    .font(Theme.mono).foregroundStyle(Theme.textSecondary)
                                    .gridColumnAlignment(.trailing)
                            }
                        }
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
}
