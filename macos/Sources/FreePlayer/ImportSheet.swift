import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ImportStep {
    case selecting, scanning, confirm, importing, done, error
}

/// Multi-step import wizard (source → scan → review → import).
struct ImportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: ImportStep = .selecting
    @State private var sourceDir = ""
    @State private var libraryDir = ""
    @State private var files: [String] = []
    @State private var scanProgress = false
    @State private var importProgress = 0
    @State private var totalFiles = 0
    @State private var result: ImportResult?
    @State private var errorMessage = ""
    @State private var errorDetails: [(file: String, error: String)] = []
    @State private var didStart = false

    // Keep security-scoped URLs alive while scanning/importing.
    @State private var scopedURLs: [URL] = []
    @State private var pendingSource: URL?
    @State private var pendingInitialPaths: [String]?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            bodyView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 560, height: 520)
        .background(Theme.background)
        .onAppear(perform: beginFlow)
        .onDisappear { releaseAccess() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Import Music")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(model.importMode == .symlink ? "Symlink Mode" : "Copy Mode")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.panelRaised))
            Spacer()
            if step != .importing {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    @ViewBuilder private var bodyView: some View {
        VStack(spacing: 16) {
            stepIndicator
            switch step {
            case .selecting:
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Select a folder containing your music files...")
                        .foregroundStyle(Theme.textSecondary)
                    Button("Choose Folder...") {
                        didStart = false
                        pickSourceDir()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .frame(maxHeight: .infinity)
            case .scanning:
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Scanning \(sourceDir)...")
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(files.count) files found")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxHeight: .infinity)
            case .confirm:
                confirmView
            case .importing:
                VStack(spacing: 10) {
                    ProgressView(value: Double(importProgress), total: Double(max(totalFiles, 1)))
                        .frame(width: 320)
                    Text("Importing tracks... This may take a moment.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(importProgress) / \(totalFiles)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxHeight: .infinity)
            case .done:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.green)
                    Text("Import Complete")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 32) {
                        if let result {
                            VStack(spacing: 2) {
                                Text("\(result.imported)")
                                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.green)
                                Text("imported").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            }
                            if !result.errors.isEmpty {
                                VStack(spacing: 2) {
                                    Text("\(result.errors.count)")
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.orange)
                                    Text("failed").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            case .error:
                VStack(spacing: 12) {
                    Image(systemName: "xmark.octagon")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.danger)
                    Text("Import Failed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    if !errorDetails.isEmpty {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(Array(errorDetails.prefix(10)), id: \.file) { e in
                                    HStack {
                                        Text((e.file as NSString).lastPathComponent)
                                            .font(Theme.mono)
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Text(e.error)
                                            .font(Theme.mono)
                                            .foregroundStyle(Theme.danger)
                                    }
                                    .font(.system(size: 11))
                                }
                                if errorDetails.count > 10 {
                                    Text("+ \(errorDetails.count - 10) more errors")
                                        .font(Theme.mono)
                                        .foregroundStyle(Theme.textTertiary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 4)
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 140)
                        .background(Theme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(["Select Source", "Scan", "Review", "Import"], id: \.self) { label in
                HStack(spacing: 6) {
                    Circle()
                        .fill(stepActive(label) ? Theme.accent : Theme.border)
                        .frame(width: 8, height: 8)
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(stepActive(label) ? Theme.textPrimary : Theme.textTertiary)
                }
                if label != "Import" {
                    Rectangle().fill(Theme.border.opacity(0.5)).frame(width: 20, height: 1)
                }
            }
            Spacer()
        }
    }

    private func stepActive(_ label: String) -> Bool {
        let order: [String] = ["Select Source", "Scan", "Review", "Import"]
        let currentIdx = order.firstIndex(of: label) ?? 0
        let stepIdx: Int
        switch step {
        case .selecting: stepIdx = 0
        case .scanning: stepIdx = 1
        case .confirm: stepIdx = 2
        case .importing, .done, .error: stepIdx = 3
        }
        return currentIdx <= stepIdx
    }

    private var confirmView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 6) {
                summaryRow("Source", sourceDir)
                summaryRow("Library", libraryDir)
                HStack {
                    Text("Files found")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .frame(width: 110, alignment: .leading)
                    Text("\(files.count) audio files")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.accent)
                    Spacer()
                }
            }
            .padding(12)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text("Files to import")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(files.prefix(20)), id: \.self) { f in
                            HStack(spacing: 6) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textTertiary)
                                Text(f.replacingOccurrences(of: sourceDir, with: ""))
                                    .font(Theme.mono)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .font(.system(size: 11))
                        }
                        if files.count > 20 {
                            Text("+ \(files.count - 20) more files")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 220)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(Theme.mono)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    @ViewBuilder private var footer: some View {
        HStack {
            Spacer()
            switch step {
            case .confirm:
                Button("Back") {
                    didStart = false
                    step = .selecting
                    files = []
                    result = nil
                    errorMessage = ""
                    errorDetails = []
                }
                .buttonStyle(.bordered)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Import \(files.count) Files") {
                    runImport()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            case .done:
                Button("View Library") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            case .error:
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Try Again") {
                    didStart = false
                    step = .selecting
                    errorMessage = ""
                    errorDetails = []
                    result = nil
                    beginFlow()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            default:
                EmptyView()
            }
        }
        .padding(12)
    }

    // ── Flow ──

    private func beginFlow() {
        guard !didStart else { return }
        didStart = true

        // Let the sheet finish presenting before showing the panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let paths = self.model.importInitialPaths, !paths.isEmpty {
                let libDir = Database.shared.getSetting("library_dir", nil) ?? ""
                if libDir.isEmpty {
                    self.pendingInitialPaths = paths
                    self.pickLibraryDir()
                } else {
                    self.handleInitialPaths(paths, libDir: libDir)
                }
            } else {
                self.pickSourceDir()
            }
        }
    }

    private func pickSourceDir() {
        let panel = NSOpenPanel()
        panel.title = "Select directory containing music files"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        // App-modal, no parent window: beginSheetModal(for:) on the key window
        // (the sheet itself, or a window that already hosts the ImportSheet
        // sheet) leaves the panel's Open button unresponsive.
        panel.begin { response in
            // Defer one runloop tick: the previous modal session must fully
            // unwind before a second panel's begin() starts, otherwise the
            // second panel never opens / never completes.
            DispatchQueue.main.async {
                guard response == .OK, let url = panel.url else {
                    NSLog("[import] source panel cancelled")
                    self.step = .selecting
                    self.didStart = false
                    return
                }
                NSLog("[import] source picked: %@", url.path)
                self.keepAccess(url)
                let libDir = Database.shared.getSetting("library_dir", nil) ?? ""
                if libDir.isEmpty {
                    self.pendingSource = url
                    self.pickLibraryDir()
                } else {
                    self.proceedAfterSourcePicked(url, libDir: libDir)
                }
            }
        }
    }

    private func pickLibraryDir() {
        let panel = NSOpenPanel()
        panel.title = "Select destination library directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.begin { response in
            DispatchQueue.main.async {
                guard response == .OK, let url = panel.url else {
                    NSLog("[import] library panel cancelled")
                    self.step = .selecting
                    self.didStart = false
                    return
                }
                NSLog("[import] library picked: %@", url.path)
                self.keepAccess(url)
                let libDir = url.path
                Database.shared.setSetting("library_dir", libDir)

                if let source = self.pendingSource {
                    self.pendingSource = nil
                    self.proceedAfterSourcePicked(source, libDir: libDir)
                } else if let paths = self.pendingInitialPaths {
                    self.pendingInitialPaths = nil
                    self.handleInitialPaths(paths, libDir: libDir)
                } else {
                    self.dismiss()
                }
            }
        }
    }

    /// Starts security-scoped access so background scan/import can read the
    /// picked folders; held until the flow finishes (or sheet dismisses).
    private func keepAccess(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            scopedURLs.append(url)
        }
    }

    private func releaseAccess() {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        scopedURLs = []
    }

    private func proceedAfterSourcePicked(_ url: URL, libDir: String) {
        sourceDir = url.path
        libraryDir = libDir
        scan(url.path)
    }

    private func handleInitialPaths(_ paths: [String], libDir: String) {
        libraryDir = libDir

        step = .scanning
        DispatchQueue.global(qos: .userInitiated).async {
            var allFiles: [String] = []
            let scanner = ImportManager()
            for p in paths {
                if scanner.isDirectory(p) {
                    allFiles.append(contentsOf: scanner.scanAudioFiles(root: p))
                } else if ExtractedMetadata.isAudioFile(p) {
                    allFiles.append(p)
                }
            }
            let unique = Array(Set(allFiles))
            DispatchQueue.main.async {
                self.sourceDir = paths.count == 1 ? paths[0] : "\(paths.count) paths (\(paths[0])...)"
                self.files = unique
                self.step = unique.isEmpty ? .error : .confirm
                if unique.isEmpty {
                    self.errorMessage = "No supported audio files found in the selected paths"
                }
            }
        }
    }

    private func scan(_ dir: String) {
        step = .scanning
        DispatchQueue.global(qos: .userInitiated).async {
            let found = ImportManager().scanAudioFiles(root: dir)
            DispatchQueue.main.async {
                files = found
                step = found.isEmpty ? .error : .confirm
                NSLog("[import] scan of %@ -> %d files", dir, found.count)
                if found.isEmpty {
                    errorMessage = "No audio files found in that directory"
                }
            }
        }
    }

    private func runImport() {
        step = .importing
        totalFiles = files.count
        importProgress = 0
        errorDetails = []
        NSLog("[import] starting import of %d files -> %@", files.count, libraryDir)
        ImportManager().importFiles(
            files: files,
            libraryDir: libraryDir,
            importMode: model.importMode,
            progress: { done, _ in
                self.importProgress = done
            }
        ) { result in
            self.result = result
            NSLog("[import] finished: %d imported, %d skipped, %d errors",
                  result.imported, result.skipped, result.errors.count)
            if result.imported == 0 && !result.errors.isEmpty {
                errorMessage = "All \(result.errors.count) files failed to import"
                errorDetails = result.errors
                step = .error
            } else {
                step = .done
            }
            model.loadTracks()
            model.isSetup = true
            releaseAccess()
        }
    }
}
