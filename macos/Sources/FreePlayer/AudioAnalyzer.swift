import Foundation
import Accelerate

/// FFT analysis of the live audio stream. Mirrors the Web Audio AnalyserNode
/// behavior the old UI used: byte time-domain + byte frequency data with a
/// -90..-10 dB range.
final class AudioAnalyzer {

    private let fftSize: Int = 2048
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let binCount: Int

    private var freqData = [UInt8]()
    private var timeData = [UInt8]()
    private var hasData = false

    // AnalyserNode.smoothingTimeConstant = 0.65: exponential smoothing on the
    // dB-scaled spectrum so bars don't flicker (Web audioEngine.js:33-36).
    private var smoothedDb = [Float]()
    private let smoothing: Float = 0.65

    init() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        binCount = fftSize / 2
        freqData = [UInt8](repeating: 0, count: binCount)
        timeData = [UInt8](repeating: 0, count: binCount)
        smoothedDb = [Float](repeating: 0, count: binCount)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Feed the latest mono samples; updates freqData/timeData.
    func update(samples: [Float]) {
        var padded = [Float](repeating: 0, count: fftSize)
        let n = min(samples.count, fftSize)
        if n > 0 {
            padded.replaceSubrange(0..<n, with: samples[0..<n])
        }

        // ── Time domain (byte, 0-255, 128 = zero) — raw samples, no window
        // (matches WebAudio getByteTimeDomainData).
        for i in 0..<binCount {
            let v = padded[i]
            timeData[i] = UInt8(clamping: Int((v + 1.0) * 127.5))
        }

        // ── FFT → magnitude spectrum ──
        var realp = [Float](repeating: 0, count: binCount)
        var imagp = [Float](repeating: 0, count: binCount)
        var magnitudes = [Float](repeating: 0, count: binCount)
        realp.withUnsafeMutableBufferPointer { realBuffer in
            imagp.withUnsafeMutableBufferPointer { imagBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                padded.withUnsafeBufferPointer { buf in
                    buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: binCount) { dspComplex in
                        vDSP_ctoz(dspComplex, 2, &split, 1, vDSP_Length(binCount))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                magnitudes.withUnsafeMutableBufferPointer { magnitudeBuffer in
                    vDSP_zvabs(&split, 1, magnitudeBuffer.baseAddress!, 1, vDSP_Length(binCount))
                }
            }
        }

        // magnitudes
        // scale: /fftSize, then dB
        var scale = Float(1.0 / Double(fftSize))
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(binCount))

        let minDb: Float = -90
        let maxDb: Float = -10
        for k in 0..<binCount {
            let mag = max(magnitudes[k], 1e-12)
            let db = 20 * log10(mag)
            // smoothingTimeConstant 0.65: next = 0.65*prev + 0.35*current
            smoothedDb[k] = smoothing * smoothedDb[k] + (1 - smoothing) * db
            let clamped = min(max((smoothedDb[k] - minDb) / (maxDb - minDb), 0), 1)
            freqData[k] = UInt8(clamping: Int(clamped * 255))
        }
        hasData = true
    }

    var hasAnyData: Bool { hasData }

    func getFrequencyData() -> [UInt8] { freqData }

    func getTimeData() -> [UInt8] { timeData }
}
