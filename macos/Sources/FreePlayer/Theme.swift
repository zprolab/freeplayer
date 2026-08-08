import SwiftUI

/// Light content area + dark sidebar palette matching the original App.css design.
enum Theme {
    // ── Content area (light) ──
    static let background = Color(red: 0.980, green: 0.980, blue: 0.980)      // #fafafa
    static let panel = Color.white                                              // #ffffff
    static let panelRaised = Color(red: 0.965, green: 0.965, blue: 0.965)     // #f5f5f5
    static let border = Color(red: 0.859, green: 0.859, blue: 0.859)          // #dbdbdb
    static let borderLight = Color(red: 0.910, green: 0.910, blue: 0.910)     // #e8e8e8

    // ── Sidebar & chrome (dark) ──
    static let sidebarBg = Color(red: 0.161, green: 0.169, blue: 0.184)       // #292b2f
    static let sidebarHover = Color(red: 0.204, green: 0.212, blue: 0.231)    // #34363b
    static let sidebarActive = Color(red: 0.227, green: 0.235, blue: 0.259)   // #3a3c42
    static let playerBg = Color.white                                           // #ffffff
    static let playerBorder = Color(red: 0.859, green: 0.859, blue: 0.859)    // #dbdbdb

    // ── Accent ──
    static let accent = Color(red: 0.886, green: 0.263, blue: 0.161)          // #e24329
    static let green = Color(red: 0.063, green: 0.522, blue: 0.282)           // #108548
    static let blue = Color(red: 0.122, green: 0.459, blue: 0.796)            // #1f75cb

    // ── Text (for light background) ──
    static let textPrimary = Color(red: 0.188, green: 0.188, blue: 0.188)     // #303030
    static let textSecondary = Color(red: 0.451, green: 0.447, blue: 0.471)   // #737278
    static let textTertiary = Color(red: 0.600, green: 0.600, blue: 0.600)    // #999999

    // ── Text (for dark background) ──
    static let sidebarText = Color(red: 0.810, green: 0.810, blue: 0.816)     // #ceced0
    static let sidebarTextSecondary = Color(red: 0.600, green: 0.600, blue: 0.631) // #999da2

    // ── Misc ──
    static let danger = Color(red: 0.867, green: 0.173, blue: 0.173)          // #dd2c2c

    static let mono = Font.system(.footnote, design: .monospaced)

    // Spectrogram "thermal" palette shared with the visualizer.
    static func spectrogramColor(_ t: Double) -> (r: Int, g: Int, b: Int) {
        if t <= 0 { return (15, 15, 20) }
        if t < 0.2 {
            let s = t / 0.2
            return (Int(15 + 30 * s), Int(15 + 30 * s), Int(20 + 160 * s))
        }
        if t < 0.4 {
            let s = (t - 0.2) / 0.2
            return (Int(45 + 30 * s), Int(45 + 150 * s), Int(180 + 40 * s))
        }
        if t < 0.55 {
            let s = (t - 0.4) / 0.15
            return (Int(75 + 80 * s), Int(195 + 40 * s), Int(220 - 100 * s))
        }
        if t < 0.7 {
            let s = (t - 0.55) / 0.15
            return (Int(155 + 100 * s), Int(235 - 30 * s), Int(120 - 90 * s))
        }
        if t < 0.85 {
            let s = (t - 0.7) / 0.15
            return (255, Int(205 - 90 * s), 30)
        }
        return (255, Int(115 - 30 * ((t - 0.85) / 0.15)), 0)
    }
}

// Reusable small views
struct MusicNoteIcon: View {
    var body: some View {
        Image(systemName: "music.note")
            .foregroundStyle(Theme.textSecondary)
    }
}

struct PanelBox<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(16)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border.opacity(0.5)))
    }
}
