import Foundation

// MARK: - Voice catalog

struct ElevenLabsVoice: Identifiable, Hashable {
    let id: String
    let name: String
}

extension ElevenLabsVoice {
    static let catalog: [ElevenLabsVoice] = [
        ElevenLabsVoice(id: "pNInz6obpgDQGcFmaJgB", name: "Rachel — calm, clear"),
        ElevenLabsVoice(id: "EXAVITQu4vr4xnSDxMaL", name: "Bella — warm"),
        ElevenLabsVoice(id: "pqHfZKP75CvOlQylNhV4", name: "Adam — deep"),
        ElevenLabsVoice(id: "onwK4e9ZLuTAKqWW03F9", name: "Daniel — authoritative"),
    ]
    static let `default` = catalog[0]
}

// MARK: - Word timing (used for live highlight)

struct WordTiming {
    let word: String
    let startTime: Double
    let endTime: Double
}

// MARK: - Errors

enum ElevenLabsError: LocalizedError {
    case noAPIKey
    case unauthorized           // 401
    case forbidden              // 403
    case voiceNotFound          // 404
    case rateLimited            // 429
    case httpError(Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .noAPIKey:       return "ElevenLabs API key is missing. Add it in Settings."
        case .unauthorized:   return "ElevenLabs: Invalid API key (401). Tap the eye icon in Settings to see what's stored, then CLEAR and re-paste."
        case .forbidden:      return "ElevenLabs: Access denied (403). Check your plan limits."
        case .voiceNotFound:  return "ElevenLabs: Voice not found (404). Try a different voice in Settings."
        case .rateLimited:    return "ElevenLabs: Rate limit hit (429). Wait a moment and try again."
        case .httpError(let c): return "ElevenLabs error \(c). Check Settings."
        case .noData:         return "ElevenLabs returned an empty response."
        }
    }
}

extension ElevenLabsError {
    static func from(statusCode: Int) -> ElevenLabsError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .voiceNotFound
        case 429: return .rateLimited
        default:  return .httpError(statusCode)
        }
    }
}

// MARK: - Key validation

extension ElevenLabsService {
    /// Validates the key by hitting /v1/voices — accessible with any valid key including
    /// restricted TTS-only keys. /v1/user requires full account scope and will 401 for
    /// restricted keys even when TTS synthesis would succeed.
    static func validateKey(_ key: String) async -> String? {
        let trimmed = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isASCII && !$0.isWhitespace }
        guard !trimmed.isEmpty else { return "Key is empty." }
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!)
        req.setValue(trimmed, forHTTPHeaderField: "xi-api-key")
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 { return nil }
                return ElevenLabsError.from(statusCode: http.statusCode).localizedDescription
            }
            return "Unexpected response."
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - Private API response shapes

private struct TimestampResponse: Codable {
    let audio_base64: String
    let alignment: Alignment

    struct Alignment: Codable {
        let characters: [String]
        let character_start_times_seconds: [Double]
        let character_end_times_seconds: [Double]
    }
}

// MARK: - Service

enum ElevenLabsService {

    // Plain synthesis (no word timings). Caches the mp3 to disk.
    static func synthesize(
        text: String,
        apiKey: String,
        voiceID: String
    ) async throws -> Data {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ElevenLabsError.noAPIKey
        }
        let audioURL = diskCacheURL(for: text, voiceID: voiceID, suffix: "mp3")
        if FileManager.default.fileExists(atPath: audioURL.path),
           let cached = try? Data(contentsOf: audioURL) { return cached }

        let data = try await fetchAudio(text: text, apiKey: apiKey, voiceID: voiceID,
                                        withTimestamps: false)
        persist(data, to: audioURL)
        return data
    }

    // Synthesis + word-level timing. Caches both audio and timings separately
    // so the two cache entries are independently valid.
    static func synthesizeWithTimings(
        text: String,
        apiKey: String,
        voiceID: String
    ) async throws -> (Data, [WordTiming]) {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ElevenLabsError.noAPIKey
        }

        let audioURL   = diskCacheURL(for: text, voiceID: voiceID, suffix: "mp3")
        let timingsURL = diskCacheURL(for: text, voiceID: voiceID, suffix: "json")

        // Both halves cached → return immediately
        if FileManager.default.fileExists(atPath: audioURL.path),
           FileManager.default.fileExists(atPath: timingsURL.path),
           let audio   = try? Data(contentsOf: audioURL),
           let rawJSON = try? Data(contentsOf: timingsURL),
           let timings = try? JSONDecoder().decode([CachedWord].self, from: rawJSON) {
            return (audio, timings.map { WordTiming(word: $0.w, startTime: $0.s, endTime: $0.e) })
        }

        let jsonData = try await fetchAudio(text: text, apiKey: apiKey, voiceID: voiceID,
                                            withTimestamps: true)
        let response = try JSONDecoder().decode(TimestampResponse.self, from: jsonData)
        let audio    = Data(base64Encoded: response.audio_base64) ?? Data()
        let timings  = wordTimings(from: response.alignment)

        persist(audio, to: audioURL)
        let cachedWords = timings.map { CachedWord(w: $0.word, s: $0.startTime, e: $0.endTime) }
        if let encoded = try? JSONEncoder().encode(cachedWords) { persist(encoded, to: timingsURL) }

        return (audio, timings)
    }

    // MARK: - Cache management

    static func diskCacheURL(for text: String, voiceID: String, suffix: String) -> URL {
        let key = "\(voiceID)_\(text.hashValue)"
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return support.appendingPathComponent("audio_cache")
                      .appendingPathComponent("\(key).\(suffix)")
    }

    static func diskCacheURL(for text: String, voiceID: String) -> URL {
        diskCacheURL(for: text, voiceID: voiceID, suffix: "mp3")
    }

    static func clearCache() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        try? FileManager.default.removeItem(
            at: support.appendingPathComponent("audio_cache")
        )
    }

    // MARK: - Private helpers

    private static func fetchAudio(
        text: String,
        apiKey: String,
        voiceID: String,
        withTimestamps: Bool
    ) async throws -> Data {
        let path = withTimestamps
            ? "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/with-timestamps"
            : "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)"
        var request = URLRequest(url: URL(string: path)!)
        request.httpMethod = "POST"
        let cleanKey = apiKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isASCII && !$0.isWhitespace }
        request.setValue(cleanKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !withTimestamps {
            request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        }
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ElevenLabsError.from(statusCode: http.statusCode)
        }
        guard !data.isEmpty else { throw ElevenLabsError.noData }
        return data
    }

    private static func wordTimings(from alignment: TimestampResponse.Alignment) -> [WordTiming] {
        var words: [WordTiming] = []
        var wordStart: Double?
        var wordChars: [String] = []
        var wordEnd: Double = 0

        for i in alignment.characters.indices {
            let ch    = alignment.characters[i]
            let start = alignment.character_start_times_seconds[i]
            let end   = alignment.character_end_times_seconds[i]

            if ch == " " || ch == "\n" || ch == "\t" {
                if let ws = wordStart, !wordChars.isEmpty {
                    words.append(WordTiming(word: wordChars.joined(), startTime: ws, endTime: wordEnd))
                    wordStart = nil; wordChars = []
                }
            } else {
                if wordStart == nil { wordStart = start }
                wordChars.append(ch)
                wordEnd = end
            }
        }
        if let ws = wordStart, !wordChars.isEmpty {
            words.append(WordTiming(word: wordChars.joined(), startTime: ws, endTime: wordEnd))
        }
        return words
    }

    private static func persist(_ data: Data, to url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url)
    }
}

// Minimal Codable shape for the timing cache file
private struct CachedWord: Codable {
    let w: String   // word
    let s: Double   // startTime
    let e: Double   // endTime
}
