import Foundation
import AVFoundation
import AppKit
import Combine

enum Language: String, CaseIterable {
    case auto = ""
    case de = "de"
    case en = "en"
}

@MainActor
class DictateManager: ObservableObject {
    // MARK: - Published State
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var history: [String] = []
    @Published var vocabulary: [String] = []
    @Published var autoCorrect: Bool = false {
        didSet { saveConfig() }
    }
    @Published var saveToClipboard: Bool = false {
        didSet { saveConfig() }
    }
    @Published var language: Language = .auto {
        didSet { saveConfig() }
    }

    // MARK: - Computed Properties
    var statusIcon: String {
        if isRecording { return "waveform.circle.fill" }
        if isProcessing { return "ellipsis.circle" }
        return "waveform"
    }

    var statusText: String {
        if isRecording { return "Recording…" }
        if isProcessing { return "Processing…" }
        return "Hold ⌥ to dictate"
    }

    var hasApiKey: Bool {
        groqApiKey != nil
    }

    // MARK: - Private
    private let audioRecorder = AudioRecorder()
    private var groqApiKey: String?
    private let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".dictate-config.json")
    private let vocabPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".dictate-vocab.json")

    private let historyMax = 5

    // MARK: - Init
    init() {
        loadApiKey()
        loadConfig()
        loadVocabulary()
    }

    // MARK: - API Key
    private let apiKeyPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".groq-api-key")

    private func loadApiKey() {
        groqApiKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"]

        if groqApiKey == nil {
            if let key = try? String(contentsOf: apiKeyPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
               !key.isEmpty {
                groqApiKey = key
            }
        }
    }

    func setApiKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? trimmed.write(to: apiKeyPath, atomically: true, encoding: .utf8)
        groqApiKey = trimmed
        objectWillChange.send()
    }

    // MARK: - Config
    private func loadConfig() {
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return
        }
        autoCorrect = config.correct
        saveToClipboard = config.saveToClipboard
        language = Language(rawValue: config.language ?? "") ?? .auto
    }

    private func saveConfig() {
        let config = Config(
            correct: autoCorrect,
            language: language.rawValue.isEmpty ? nil : language.rawValue,
            saveToClipboard: saveToClipboard
        )
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configPath)
        }
    }

    // MARK: - Vocabulary
    private func loadVocabulary() {
        guard let data = try? Data(contentsOf: vocabPath),
              let vocab = try? JSONDecoder().decode(Vocabulary.self, from: data) else {
            return
        }
        vocabulary = vocab.terms
    }

    private func saveVocabulary() {
        let vocab = Vocabulary(terms: vocabulary)
        if let data = try? JSONEncoder().encode(vocab) {
            try? data.write(to: vocabPath)
        }
    }

    func addTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !vocabulary.contains(trimmed) else { return }
        vocabulary.append(trimmed)
        saveVocabulary()
    }

    func removeTerm(_ term: String) {
        vocabulary.removeAll { $0 == term }
        saveVocabulary()
    }

    func setVocabulary(_ terms: [String]) {
        vocabulary = terms
        saveVocabulary()
    }

    // MARK: - Recording
    func startRecording() {
        guard !isRecording, !isProcessing, hasApiKey else { return }

        isRecording = true
        playStartSound()
        audioRecorder.startRecording()
    }

    func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        isProcessing = true
        playStopSound()

        Task {
            await processRecording()
        }
    }

    private func processRecording() async {
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        guard let audioData = audioRecorder.stopRecording() else {
            showNotification(title: "Dictate", body: "No audio recorded")
            return
        }

        // Check minimum duration (0.3 seconds at 16kHz = 4800 samples)
        if audioData.count < 4800 {
            showNotification(title: "Dictate", body: "Hold Option longer")
            return
        }

        do {
            // Create temp WAV file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".wav")
            try writeWAV(audioData: audioData, to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            // Transcribe
            var text = try await transcribe(audioURL: tempURL)

            // Auto-correct if enabled
            if autoCorrect && !text.isEmpty {
                text = try await correctText(text)
            }

            guard !text.isEmpty else { return }

            // Add to history
            await MainActor.run {
                history.insert(text, at: 0)
                if history.count > historyMax {
                    history.removeLast()
                }
            }

            // Paste text - genau wie Python-Version
            pasteTextSync(text)

        } catch {
            showNotification(title: "Dictate Error", body: error.localizedDescription)
        }
    }

    // Exakt wie die Python paste_text() Funktion
    private nonisolated func pasteTextSync(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general

        // 1. Vorherigen Inhalt speichern
        let previous = pasteboard.string(forType: .string)

        // 2. Text kopieren
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. 0.1s warten
        Thread.sleep(forTimeInterval: 0.1)

        // 4. Cmd+V via osascript
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"System Events\" to keystroke \"v\" using command down"]
        try? process.run()
        process.waitUntilExit()

        // 5. 0.15s warten
        Thread.sleep(forTimeInterval: 0.15)

        // 6. Clipboard wiederherstellen
        pasteboard.clearContents()
        pasteboard.setString(previous ?? "", forType: .string)
    }

    // MARK: - Groq API
    private func transcribe(audioURL: URL) async throws -> String {
        guard let apiKey = groqApiKey else {
            throw DictateError.noApiKey
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Model
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("whisper-large-v3-turbo\r\n")

        // Response format
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.append("text\r\n")

        // Language (if not auto)
        if !language.rawValue.isEmpty {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            body.append("\(language.rawValue)\r\n")
        }

        // Prompt (vocabulary context)
        if !vocabulary.isEmpty {
            let prompt = "Context terms: " + vocabulary.joined(separator: ", ") + "."
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            body.append("\(prompt)\r\n")
        }

        // Audio file
        let audioData = try Data(contentsOf: audioURL)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")

        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DictateError.apiError(errorText)
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func correctText(_ text: String) async throws -> String {
        guard let apiKey = groqApiKey else {
            throw DictateError.noApiKey
        }

        let termsStr = vocabulary.isEmpty ? "(none)" : vocabulary.joined(separator: ", ")
        let systemPrompt = """
            You are a transcription corrector. The user dictated text via Whisper. \
            Your tasks:
            1. Correct obvious mis-hearings of words from this glossary: \(termsStr)
            2. Remove filler words (um, uh, like, so, you know).
            3. Format into clean, natural text with proper punctuation.
            4. Preserve 100% of the meaning — do not omit or invent content.
            Reply with ONLY the corrected text, no commentary.
            """

        let requestBody: [String: Any] = [
            "model": "llama-3.3-70b-versatile",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 500,
            "temperature": 0.2
        ]

        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            // If correction fails, return original text
            return text
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }

    // MARK: - Audio
    private func playStartSound() {
        SoundGenerator.shared.playStartSound()
    }

    private func playStopSound() {
        SoundGenerator.shared.playStopSound()
    }

    private func writeWAV(audioData: [Int16], to url: URL) throws {
        var header = WAVHeader(
            chunkSize: UInt32(36 + audioData.count * 2),
            subchunk2Size: UInt32(audioData.count * 2)
        )

        var data = Data()
        data.append(Data(bytes: &header, count: MemoryLayout<WAVHeader>.size))
        audioData.withUnsafeBufferPointer { buffer in
            data.append(buffer)
        }

        try data.write(to: url)
    }

    private func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        NSUserNotificationCenter.default.deliver(notification)
    }
}

// MARK: - Data Extension
private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func append<T>(_ buffer: UnsafeBufferPointer<T>) {
        append(contentsOf: UnsafeRawBufferPointer(buffer))
    }
}

// MARK: - Models
struct Config: Codable {
    var correct: Bool
    var language: String?
    var saveToClipboard: Bool

    enum CodingKeys: String, CodingKey {
        case correct
        case language
        case saveToClipboard = "save_to_clipboard"
    }
}

struct Vocabulary: Codable {
    var terms: [String]
}

struct WAVHeader {
    var riff: (UInt8, UInt8, UInt8, UInt8) = (0x52, 0x49, 0x46, 0x46) // "RIFF"
    var chunkSize: UInt32
    var wave: (UInt8, UInt8, UInt8, UInt8) = (0x57, 0x41, 0x56, 0x45) // "WAVE"
    var fmt: (UInt8, UInt8, UInt8, UInt8) = (0x66, 0x6D, 0x74, 0x20)  // "fmt "
    var subchunk1Size: UInt32 = 16
    var audioFormat: UInt16 = 1      // PCM
    var numChannels: UInt16 = 1      // Mono
    var sampleRate: UInt32 = 16000
    var byteRate: UInt32 = 32000     // sampleRate * numChannels * bitsPerSample/8
    var blockAlign: UInt16 = 2       // numChannels * bitsPerSample/8
    var bitsPerSample: UInt16 = 16
    var data: (UInt8, UInt8, UInt8, UInt8) = (0x64, 0x61, 0x74, 0x61) // "data"
    var subchunk2Size: UInt32
}

enum DictateError: LocalizedError {
    case noApiKey
    case apiError(String)
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "GROQ_API_KEY not set"
        case .apiError(let message):
            return message
        case .recordingFailed:
            return "Recording failed"
        }
    }
}
