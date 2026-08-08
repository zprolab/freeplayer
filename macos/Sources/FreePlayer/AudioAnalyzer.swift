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

    init() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        binCount = fftSize / 2
        freqData = [UInt8](repeating: 0, count: binCount)
        timeData = [UInt8](repeating: 0, count: binCount)
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

        // ── Time domain (byte, 0-255, 128 = zero) ──
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        var winSamples = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(padded, 1, window, 1, &winSamples, 1, vDSP_Length(fftSize))

        for i in 0..<binCount {
            let v = winSamples[i]
            timeData[i] = UInt8(clamping: Int((v + 1.0) * 127.5))
        }

        // ── FFT → magnitude spectrum ──
        var realp = [Float](repeating: 0, count: binCount)
        var imagp = [Float](repeating: 0, count: binCount)
        var split = DSPSplitComplex(realp: &realp, imagp: &imagp)
        winSamples.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: binCount) { dspComplex in
                vDSP_ctoz(dspComplex, 2, &split, 1, vDSP_Length(binCount))
            }
        }
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        // magnitudes
        var magnitudes = [Float](repeating: 0, count: binCount)
        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(binCount))
        // scale: /fftSize, then dB
        var scale = Float(1.0 / Double(fftSize))
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(binCount))

        let minDb: Float = -90
        let maxDb: Float = -10
        for k in 0..<binCount {
            let mag = max(magnitudes[k], 1e-12)
            let db = 20 * log10(mag)
            let clamped = min(max((db - minDb) / (maxDb - minDb), 0), 1)
            freqData[k] = UInt8(clamping: Int(clamped * 255))
        }
        hasData = true
    }

    var hasAnyData: Bool { hasData }

    func getFrequencyData() -> [UInt8] { freqData }

    func getTimeData() -> [UInt8] { timeData }
}
