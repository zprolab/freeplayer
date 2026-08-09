import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var trayEnabled = true
    @State private var trayNotify = true
    @State private var startOnBoot = false
    @State private var showResetConfirm = false
    @AppStorage("liquid_glass_enabled") private var liquidGlassEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appearanceSection
                importModeSection
                libraryDirSection
                playbackSection
                dangerZoneSection
            }
            .frame(maxWidth: 620)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.background)
        .onAppear {
            trayEnabled = Database.shared.getBoolSetting("tray_enabled", fallback: true)
            trayNotify = Database.shared.getBoolSetting("tray_notify", fallback: true)
            startOnBoot = TrayController.shared.loginItemEnabled()
        }
        .confirmationDialog(
            "Reset Database",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) {
                model.resetDatabase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all tracks, play history, playlists, and settings. Your music files on disk will not be touched. This action cannot be undone.")
        }
    }

    // ── Card section container ──

    private func cardSection<Content: View>(
        danger: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(20)
            .systemGlassSurface(
                cornerRadius: 6,
                tint: danger ? Theme.danger.opacity(0.06) : nil,
                fallbackFill: Theme.panel
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(danger ? Theme.danger.opacity(0.5) : Theme.border, lineWidth: 1)
            )
    }

    private var appearanceSection: some View {
        cardSection {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Appearance")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Use system Liquid Glass across FreePlayer. The equalizer always keeps its glass controls.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Toggle("Liquid Glass", isOn: $liquidGlassEnabled)
                    .toggleStyle(.switch)
                    .tint(.accentColor)
            }
        }
    }

    // ── Single row with divider ──

    private func row<Content: View>(
        hasDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack { content() }
                .padding(.vertical, 12)
            if hasDivider {
                Divider().foregroundStyle(Theme.border)
            }
        }
    }

    // ── Import Mode ──

    private var importModeSection: some View {
        cardSection {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Mode")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Choose how files are added to your library when importing music.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: 12) {
                    importModeCard(.copy, title: "Copy Files", hint: "Duplicate files into library directory")
                    importModeCard(.symlink, title: "Symlink", hint: "Create symbolic links (saves disk space)")
                }
            }
        }
    }

    private func importModeCard(_ mode: ImportMode, title: String, hint: String) -> some View {
        let selected = model.importMode == mode
        return Button {
            model.setImportMode(mode)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(selected ? Theme.accent : Theme.border, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 10, height: 10)
                        .opacity(selected ? 1 : 0)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(14)
            .systemGlassSurface(
                cornerRadius: 6,
                interactive: true,
                tint: selected ? Theme.accent.opacity(0.14) : nil,
                fallbackFill: selected ? Theme.accent.opacity(0.08) : Theme.panel
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // ── Library Directory ──

    private var libraryDirSection: some View {
        cardSection {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library Directory")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Where your organized music files and symlinks are stored.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    if model.libraryDir.isEmpty {
                        Text("No library directory set")
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        Text(model.libraryDir)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    Button("Change...") {
                        model.selectLibraryDir()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .systemGlassSurface(cornerRadius: 8, fallbackFill: Theme.panelRaised)
            }
        }
    }

    // ── Playback ──

    private var playbackSection: some View {
        cardSection {
            VStack(alignment: .leading, spacing: 0) {
                // Section header
                VStack(alignment: .leading, spacing: 2) {
                    Text("Playback")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Default playback preferences.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.bottom, 14)

                // Default Volume
                row {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Volume")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Set the starting volume for playback")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { model.defaultVolume },
                            set: { model.setDefaultVolume($0) }
                        ), in: 0...1)
                        .frame(width: 160)
                        Text("\(Int(model.defaultVolume * 100))%")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                // Default Visualizer
                row {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Visualizer")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Visualization shown on Now Playing view")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(VisualizerMode.allCases, id: \.self) { mode in
                            Button {
                                model.setDefaultVisualizer(mode)
                            } label: {
                                Text(mode == .waveform ? "Waveform" : mode == .spectrogram ? "Spectrogram" : "Off")
                                    .font(.system(size: 12))
                                    .foregroundStyle(model.defaultVisualizer == mode ? .white : Theme.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(model.defaultVisualizer == mode ? Theme.accent : .clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                }

                row {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Fetch Lyrics & Covers")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Automatically download missing lyrics (LRCLIB) and album art (iTunes) when playing a track")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.autoFetchMeta },
                        set: { model.setAutoFetchMeta($0) }
                    ))
                    .toggleStyle(.switch)
                    .tint(Theme.toggleChecked)
                    .labelsHidden()
                }

                row {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Backfill Missing Metadata")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                        Text(backfillDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button(model.metadataBackfillProgress == nil ? "Fetch Missing" : "Fetching...") {
                        model.startMetadataBackfill()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.metadataBackfillProgress != nil || model.tracks.isEmpty)
                }

                // Close to Tray
                row(hasDivider: trayEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Close to Tray")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Minimize to system tray instead of quitting when closing the window")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $trayEnabled)
                        .toggleStyle(.switch)
                        .tint(Theme.toggleChecked)
                        .labelsHidden()
                        .onChange(of: trayEnabled) { value in
                            model.setTrayEnabled(value)
                        }
                }

                if trayEnabled {
                    // Tray Notification
                    row {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tray Notification")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Show a notification when the app is minimized to the system tray")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $trayNotify)
                            .toggleStyle(.switch)
                            .tint(Theme.toggleChecked)
                            .labelsHidden()
                            .onChange(of: trayNotify) { value in
                                model.setTrayNotify(value)
                            }
                    }

                    // Launch at Login
                    row(hasDivider: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at Login")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Automatically start FreePlayer when you log in")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $startOnBoot)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: startOnBoot) { value in
                                model.setStartOnBoot(value)
                            }
                    }
                }
            }
        }
    }

    private var backfillDescription: String {
        guard let progress = model.metadataBackfillProgress else {
            return "Fetch lyrics and covers for \(model.tracks.count) tracks that are missing them"
        }
        var parts = ["Fetching \(progress.done)/\(progress.total)", "\(progress.saved) saved"]
        if progress.failed > 0 { parts.append("\(progress.failed) failed") }
        if progress.noMatch > 0 { parts.append("\(progress.noMatch) no match") }
        return parts.joined(separator: " · ")
    }

    // ── Danger Zone ──

    private var dangerZoneSection: some View {
        cardSection(danger: true) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Danger Zone")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                    Text("Irreversible actions. Proceed with caution.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset Database")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Remove all tracks, play history, and playlists. Files on disk are not affected.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button("Reset...") {
                        showResetConfirm = true
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(Theme.danger, lineWidth: 1))
                    .foregroundStyle(Theme.danger)
                }
            }
        }
    }
}
