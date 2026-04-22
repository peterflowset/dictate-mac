import Foundation
import AVFoundation

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Int16] = []
    private let sampleRate: Double = 16000
    private let lock = NSLock()

    func startRecording() {
        audioBuffer = []

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode

        // Get the native format and create a converter
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz, mono, Int16
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            print("Failed to create target audio format")
            return
        }

        // Create converter if needed
        let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if let converter = converter {
                // Convert to target format
                let frameCapacity = AVAudioFrameCount(
                    Double(buffer.frameLength) * self.sampleRate / nativeFormat.sampleRate
                )
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: frameCapacity
                ) else { return }

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if status == .haveData, let int16Data = convertedBuffer.int16ChannelData {
                    let frameLength = Int(convertedBuffer.frameLength)
                    self.lock.lock()
                    for i in 0..<frameLength {
                        self.audioBuffer.append(int16Data[0][i])
                    }
                    self.lock.unlock()
                }
            } else if let floatData = buffer.floatChannelData {
                // Direct conversion if formats match enough
                let frameLength = Int(buffer.frameLength)
                self.lock.lock()
                for i in 0..<frameLength {
                    let sample = max(-1.0, min(1.0, floatData[0][i]))
                    self.audioBuffer.append(Int16(sample * 32767))
                }
                self.lock.unlock()
            }
        }

        do {
            try audioEngine.start()
            self.audioEngine = audioEngine
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    func stopRecording() -> [Int16]? {
        guard let audioEngine = audioEngine else { return nil }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        self.audioEngine = nil

        lock.lock()
        let result = audioBuffer
        audioBuffer = []
        lock.unlock()

        return result.isEmpty ? nil : result
    }
}
