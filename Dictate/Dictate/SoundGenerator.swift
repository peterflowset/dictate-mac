import AVFoundation
import Foundation

class SoundGenerator {
    static let shared = SoundGenerator()

    private let sampleRate: Double = 48000
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    private init() {
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let player = playerNode else { return }

        engine.attach(player)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            print("Audio engine start failed: \(error)")
        }
    }

    private func generateTone(frequency: Double, duration: Double = 0.06, volume: Float = 0.28) -> [Float] {
        let sampleCount = Int(sampleRate * duration)
        let fadeLength = Int(sampleRate * 0.005)

        var samples = [Float](repeating: 0, count: sampleCount)

        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            var sample = sin(2.0 * .pi * frequency * t)

            // Fade in/out envelope
            var envelope: Double = 1.0
            if i < fadeLength {
                envelope = Double(i) / Double(fadeLength)
            } else if i >= sampleCount - fadeLength {
                envelope = Double(sampleCount - i) / Double(fadeLength)
            }

            samples[i] = Float(sample * envelope) * volume
        }

        return samples
    }

    private func generateSequence(frequencies: [Double], gap: Double = 0.02) -> [Float] {
        var result = [Float]()
        let gapSamples = Int(sampleRate * gap)

        for (index, freq) in frequencies.enumerated() {
            result.append(contentsOf: generateTone(frequency: freq))
            if index < frequencies.count - 1 {
                result.append(contentsOf: [Float](repeating: 0, count: gapSamples))
            }
        }

        return result
    }

    func playStartSound() {
        // 880Hz -> 1320Hz (ascending)
        let samples = generateSequence(frequencies: [880, 1320])
        playSamples(samples)
    }

    func playStopSound() {
        // 660Hz -> 440Hz (descending)
        let samples = generateSequence(frequencies: [660, 440])
        playSamples(samples)
    }

    private func playSamples(_ samples: [Float]) {
        guard let engine = audioEngine, let player = playerNode else { return }

        if !engine.isRunning {
            try? engine.start()
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = samples[i]
        }

        player.stop()
        player.scheduleBuffer(buffer, completionHandler: nil)
        player.play()
    }
}
