import Foundation
import AVFoundation

/// Playback engine built on AVAudioEngine. Uses an AVAudioPlayerNode for
/// playback (handles MP3/FLAC/WAV/OGG/M4A/AAC/AIFF), ReplayGain applied via
/// node volume, and a tap on the main mixer that feeds the visualizer.
final class AudioEngine {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private var currentFile: AVAudioFile?
    private var framePosition: AVAudioFramePosition = 0
    private var scheduleAnchor: AVAudioFramePosition = 0

    private var gainFactor: Float = 1
    private var volumeValue: Float = 1

    // Tap → latest stereo samples (channel 0 used for FFT). Copied under lock
    // because the tap runs on a realtime thread and buffers are reused.
    private let sampleLock = NSLock()
    private var latestSamples: [Float] = []
    private var sampleRate: Double = 44100
    private(set) var hasSignal = false

    // MARK: Setup

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        installTap()
    }

    private func installTap() {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        let capacity = AVAudioFrameCount(2048)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: capacity, format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let ch0 = data[0]
            let samples = Array(UnsafeBufferPointer(start: ch0, count: frames))
            self.sampleLock.lock()
            self.latestSamples = samples
            self.hasSignal = samples.contains { abs($0) > 0.0001 }
            self.sampleLock.unlock()
        }
    }

    // MARK: Public state

    var isPlaying: Bool { player.isPlaying }

    /// Current playhead frame, tracked from the node's render timeline so
    /// pause/resume/seek stay accurate.
    func currentFrame() -> AVAudioFramePosition {
        if let nodeTime = player.lastRenderTime,
           let playerTime = player.playerTime(forNodeTime: nodeTime) {
            return scheduleAnchor + playerTime.sampleTime
        }
        return framePosition
    }

    var currentTime: Double {
        guard let file = currentFile else { return 0 }
        return Double(currentFrame()) / file.processingFormat.sampleRate
    }

    var duration: Double {
        guard let file = currentFile else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Copy of the latest FFT-ready mono samples (channel 0).
    func latestMonoSamples() -> [Float] {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        return latestSamples
    }

    // MARK: Control

    func load(url: URL) throws {
        player.stop() // clears any pending scheduled segments from the previous file
        let file = try AVAudioFile(forReading: url)
        currentFile = file
        framePosition = 0
        scheduleAnchor = 0
        sampleLock.lock()
        latestSamples = []
        hasSignal = false
        sampleLock.unlock()
    }

    func play() throws {
        guard let file = currentFile else { return }
        player.stop() // drop any paused schedule so we always start from framePosition
        if !engine.isRunning {
            try engine.start()
        }
        let remaining = file.length - framePosition
        guard remaining > 0 else { return }
        scheduleAnchor = framePosition
        player.scheduleSegment(file,
                               startingFrame: framePosition,
                               frameCount: AVAudioFrameCount(remaining),
                               at: nil)
        player.play()
    }

    /// Resume after a pause without re-scheduling (the paused schedule resumes).
    func resume() {
        guard currentFile != nil else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        player.play()
    }

    func pause() {
        guard player.isPlaying else { return }
        framePosition = currentFrame()
        player.pause()
    }

    func stop() {
        player.stop()
    }

    func seek(to time: Double) {
        guard let file = currentFile else { return }
        let wasPlaying = player.isPlaying
        if wasPlaying {
            framePosition = currentFrame()
        }
        player.stop()
        let newFrame = max(0, min(AVAudioFramePosition(time * file.processingFormat.sampleRate),
                                  file.length - 1))
        framePosition = newFrame
        // Always re-schedule: stop() drops the paused segment, so a seek while
        // paused must rebuild it (resume() only calls play()).
        if !engine.isRunning {
            try? engine.start()
        }
        let remaining = file.length - framePosition
        guard remaining > 0 else { return }
        scheduleAnchor = framePosition
        player.scheduleSegment(file,
                               startingFrame: framePosition,
                               frameCount: AVAudioFrameCount(remaining),
                               at: nil)
        if wasPlaying {
            player.play()
        }
    }

    /// ReplayGain volume (in dB). Combined with the master volume before
    /// hitting the player node, so one doesn't clobber the other.
    func setGain(gainDb: Double) {
        gainFactor = Float(pow(10, gainDb / 20.0))
        applyVolume()
    }

    func setVolume(_ volume: Double) {
        volumeValue = Float(max(0.0, min(volume, 1.0)))
        applyVolume()
    }

    /// Combined output volume currently applied to the player node
    /// (gain × volume). Exposed for tests.
    var outputVolume: Float { player.volume }

    private func applyVolume() {
        player.volume = gainFactor * volumeValue
    }

    /// Reset the "signal" latch so idle displays don't draw stale data.
    func resetSignal() {
        sampleLock.lock()
        hasSignal = false
        sampleLock.unlock()
    }
}
